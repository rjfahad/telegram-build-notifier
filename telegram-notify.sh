#!/bin/bash
#
# telegram-notify.sh - Reusable Telegram build notification for Android ROM builds.
#
# Works with ANY AOSP-based ROM (LineageOS, ArrowOS, PixelExperience, EvolutionX, AOSP, ...).
# Source this file (or use the notify-build wrapper) after setting up your build env:
#
#   source $ANDROID_BUILD_TOP/build/envsetup.sh
#   lunch <product>-<variant>
#   notify-build mka bacon
#
# Or use the auto-hook (see install.sh) so every `m`, `mka`, `mm`, ... notifies automatically.
#
# Configuration is read from (in order of priority):
#   1. Already-exported environment variables
#   2. The config file: ~/.config/telegram-build-notifier.env (or $TELEGRAM_NOTIFY_CONFIG)

_DEFAULT_TG_CONFIG="${TELEGRAM_NOTIFY_CONFIG:-$HOME/.config/telegram-build-notifier.env}"

_tg_load_config() {
    # Only apply non-empty values from the config file, so existing
    # environment variables (e.g. from .bashrc) always take priority.
    [ -f "$_DEFAULT_TG_CONFIG" ] || return 0
    local line key val
    while IFS= read -r line; do
        case "$line" in
            \#*|"") continue ;;
            *"="*)
                key="${line%%=*}"
                key="${key#export }"          # tolerate a leading `export`
                key="${key#"export"}"         # tolerate `export` without space
                key="${key// /}"
                val="${line#*=}"
                val="${val#\"}"; val="${val%\"}"
                [ -n "$key" ] && [ -n "$val" ] && export "$key=$val"
                ;;
        esac
    done < "$_DEFAULT_TG_CONFIG"
}

# Determine the top of the Android tree, if any.
_tg_gettop() {
    if command -v gettop >/dev/null 2>&1; then
        local t=$(gettop 2>/dev/null)
        [ -n "$t" ] && { echo "$t"; return 0; }
    fi
    if [ -n "$ANDROID_BUILD_TOP" ] && [ -f "$ANDROID_BUILD_TOP/build/make/core/envsetup.mk" ]; then
        echo "$ANDROID_BUILD_TOP"; return 0
    fi
    if [ -n "$OUT" ] && [ -f "$OUT/../../../../build/make/core/envsetup.mk" ]; then
        (cd "$OUT/../../../../" && pwd); return 0
    fi
    return 1
}

# Escape a string for Telegram MarkdownV2.
_tg_escape() {
    printf '%s' "$1" | sed 's/[`*~>#+=|{}.!()-]/\\&/g'
}

# send_build_notification <exit_code> [build_time]
# Sends a Telegram success (with banner image + SCP download command) or
# failure (with error.log excerpt) notification.
function send_build_notification() {
    local ret=$1
    local build_time=$2

    _tg_load_config

    if [ -z "${TELEGRAM_BOT_TOKEN:-}" ] || [ -z "${TELEGRAM_CHAT_ID:-}" ]; then
        echo "telegram-notify: TELEGRAM_BOT_TOKEN/TELEGRAM_CHAT_ID not set, skipping notification" >&2
        return 0
    fi

    local server_ip="${SERVER_IP:-}"
    local ssh_user="${SSH_USER:-}"
    local product_prefix="${PRODUCT_PREFIX:-lineage_}"
    local zip_pattern="${ZIP_PATTERN:-lineage-*.zip}"

    local device="$(echo "${TARGET_PRODUCT:-}" | sed "s/^${product_prefix}//")"
    local top=""
    _tg_gettop >/dev/null 2>&1 && top=$(_tg_gettop)
    [ -z "$top" ] && top="$(pwd)"

    local message
    local out_dir="$top/out"

    if [ $ret -eq 0 ]; then
        local zipfile=""
        if [ -n "$OUT" ]; then
            zipfile=$(find "$OUT" -maxdepth 1 -type f -name "$zip_pattern" -printf '%T@ %p\n' 2>/dev/null | sort -rn | head -1 | cut -d' ' -f2-)
        fi
        [ -z "$zipfile" ] && [ -d "$out_dir/target" ] && zipfile=$(find "$out_dir"/target/product -maxdepth 2 -type f -name "$zip_pattern" -printf '%T@ %p\n' 2>/dev/null | sort -rn | head -1 | cut -d' ' -f2-)

        if [ -n "$zipfile" ]; then
            local zipname=$(basename "$zipfile")
            local zipsize=$(ls -lh "$zipfile" | awk '{print $5}')
            message="✅ *Build Succeeded* \(${build_time}\)

*ROM:* \`${zipname}\`
*Size:* \`${zipsize}\`
*Device:* \`${device}\`"
            if [ -n "$server_ip" ]; then
                message="${message}

*Download:*
\`scp ${ssh_user}@${server_ip}:${zipfile} .\`"
            fi
        else
            message="✅ *Build Succeeded* \(${build_time}\)

*Device:* \`${device}\`"
        fi
    else
        local errorlog="$out_dir/error.log"
        local error_output=""
        if [ -f "$errorlog" ]; then
            error_output=$(tail -15 "$errorlog" | sed 's/\x1B\[[0-9;]*[mK]//g' | _tg_escape | head -c 1500)
        fi
        message="❌ *Build Failed* \(${build_time}\)

*Device:* \`${device}\`"
        if [ -n "$error_output" ]; then
            message="${message}

*Error:*
\`\`\`
${error_output}
\`\`\`"
        fi
    fi

    local banner=""
    if [ $ret -eq 0 ]; then
        banner="${BANNER_IMAGE:-}"
        if [ -n "$banner" ] && [ ! -f "$banner" ]; then
            # try relative to ROM top
            [ -f "$top/$banner" ] && banner="$top/$banner"
            # fall back to the default "image.png" in the ROM root
            [ ! -f "$banner" ] && [ -f "$top/image.png" ] && banner="$top/image.png"
        fi
        [ -z "$banner" ] && [ -f "$top/image.png" ] && banner="$top/image.png"
    fi

    if [ -n "$banner" ] && [ -f "$banner" ]; then
        curl -s --max-time 15 -X POST \
            "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendPhoto" \
            -F "chat_id=${TELEGRAM_CHAT_ID}" \
            -F "photo=@${banner}" \
            -F "parse_mode=MarkdownV2" \
            -F "caption=${message}" >/dev/null 2>&1 && return 0
        # fall through to text-only if photo upload fails
    fi

    curl -s --max-time 10 -X POST \
        "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
        --data-urlencode "chat_id=${TELEGRAM_CHAT_ID}" \
        --data-urlencode "text=${message}" \
        -d parse_mode="MarkdownV2" >/dev/null 2>&1

    return 0
}

# notify-build <command...>
# Runs a build command and sends a Telegram notification with its outcome.
function notify-build() {
    local start_time=$(date +"%s")
    "$@"
    local ret=$?
    local end_time=$(date +"%s")
    local tdiff=$(($end_time - $start_time))
    local hours=$(($tdiff / 3600))
    local mins=$((($tdiff % 3600) / 60))
    local secs=$(($tdiff % 60))
    local time_str=""
    if [ $hours -gt 0 ]; then
        time_str=$(printf "%02g:%02g:%02g" $hours $mins $secs)
    elif [ $mins -gt 0 ]; then
        time_str=$(printf "%02g:%02g" $mins $secs)
    else
        time_str="${secs}s"
    fi
    send_build_notification $ret "$time_str"
    return $ret
}