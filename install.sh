#!/bin/bash
#
# install.sh - Install the Telegram build notifier.
#
# Usage:
#   ./install.sh [ROM_ROOT]
#
# ROM_ROOT defaults to the current directory. It is the Android source tree
# whose build/make/envsetup.sh will be patched with the auto-hook.
#
# What this does:
#   1. Copies config.example to ~/.config/telegram-build-notifier.env (only if missing)
#   2. Adds the source line + needed exports to ~/.bashrc (idempotent)
#   3. Patches ROM_ROOT/build/make/envsetup.sh _wrap_build() to auto-notify
#      after every build (idempotent)
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROM_ROOT="${1:-$(pwd)}"
CONFIG_FILE="$HOME/.config/telegram-build-notifier.env"
ENVSETUP="$ROM_ROOT/build/make/envsetup.sh"

echo "== telegram-build-notifier install =="
echo "  Repo:    $REPO_DIR"
echo "  ROM:     $ROM_ROOT"

# --- 1. Config file -------------------------------------------------------
if [ -f "$CONFIG_FILE" ]; then
    echo "  [skip] config already exists: $CONFIG_FILE"
else
    mkdir -p "$(dirname "$CONFIG_FILE")"
    cp "$REPO_DIR/config.example" "$CONFIG_FILE"
    echo "  [ok]   created config: $CONFIG_FILE"
    echo "         >>> Edit it and set TELEGRAM_BOT_TOKEN / TELEGRAM_CHAT_ID"
fi

# --- 2. .bashrc -----------------------------------------------------------
BASHRC="$HOME/.bashrc"
SOURCE_LINE="source $REPO_DIR/telegram-notify.sh"

if grep -qF "telegram-build-notifier" "$BASHRC" 2>/dev/null; then
    echo "  [skip] .bashrc already configured"
else
    cat >> "$BASHRC" <<EOF

# Telegram Build Notifier
$SOURCE_LINE
EOF
    echo "  [ok]   added source line to $BASHRC"
    echo "         >>> Run: source $BASHRC  (or open a new terminal)"
fi

# --- 3. Auto-hook in build/make/envsetup.sh --------------------------------
if [ ! -f "$ENVSETUP" ]; then
    echo "  [warn] $ENVSETUP not found - cannot auto-hook"
    echo "         Use the wrapper mode instead: 'notify-build mka bacon'"
else
    if grep -qF "send_build_notification" "$ENVSETUP"; then
        echo "  [skip] $ENVSETUP already hooked"
    else
        cp "$ENVSETUP" "$ENVSETUP.bak_telegram-notify"
        # Insert the notification right before `return $ret` at the end of _wrap_build().
        python3 - "$ENVSETUP" <<'PYEOF'
import sys

path = sys.argv[1]
with open(path) as f:
    content = f.read()

marker = "    echo \" ####${color_reset}\""
insert = marker + """
    local time_str=""
    if [ $hours -gt 0 ] ; then
        time_str=$(printf "%02g:%02g:%02g" $hours $mins $secs)
    elif [ $mins -gt 0 ] ; then
        time_str=$(printf "%02g:%02g" $mins $secs)
    elif [ $secs -gt 0 ] ; then
        time_str="${secs}s"
    fi
    send_build_notification $ret "$time_str\""""

assert marker in content, "marker not found in _wrap_build"

content = content.replace(marker, insert, 1)
with open(path, "w") as f:
    f.write(content)
print("  [ok]   hooked _wrap_build() in", path)
PYEOF
        echo "         Backup saved as: $ENVSETUP.bak_telegram-notify"
        echo "         NOTE: re-run install.sh after 'repo sync' (build/ is wiped)."
    fi
fi

echo "== done =="
echo "Next steps:"
echo "  1. Edit $CONFIG_FILE (bot token + chat ID)"
echo "  2. source $BASHRC"
echo "  3. Build as usual: source build/envsetup.sh && lunch <device>-<variant> && mka bacon"