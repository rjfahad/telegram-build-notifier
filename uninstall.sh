#!/bin/bash
#
# uninstall.sh - Remove the Telegram build notifier.
#
# Usage:
#   ./uninstall.sh [ROM_ROOT]
#
# Removes:
#   1. The auto-hook patch from ROM_ROOT/build/make/envsetup.sh (restores backup if available)
#   2. The source line added to ~/.bashrc
#
# Note: the config file (~/.config/telegram-build-notifier.env) and the repo
# folder are kept so you don't lose your settings. Delete them manually.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROM_ROOT="${1:-$(pwd)}"
ENVSETUP="$ROM_ROOT/build/make/envsetup.sh"

echo "== telegram-build-notifier uninstall =="

if [ -f "$ENVSETUP" ] && grep -qF "send_build_notification" "$ENVSETUP"; then
    if [ -f "$ENVSETUP.bak_telegram-notify" ]; then
        cp "$ENVSETUP.bak_telegram-notify" "$ENVSETUP"
        rm -f "$ENVSETUP.bak_telegram-notify"
        echo "  [ok]   restored $ENVSETUP from backup"
    else
        python3 - "$ENVSETUP" <<'PYEOF'
import sys, re

path = sys.argv[1]
with open(path) as f:
    content = f.read()

pat = re.compile(r'''    echo " ####\$\{color_reset\}"
    local time_str=""
    if \[ \$hours -gt 0 \] ; then
        time_str=\$\(printf "%02g:%02g:%02g" \$hours \$mins \$secs\)
    elif \[ \$mins -gt 0 \] ; then
        time_str=\$\(printf "%02g:%02g" \$mins \$secs\)
    elif \[ \$secs -gt 0 \] ; then
        time_str="\$\{secs\}s"
    fi
    send_build_notification \$ret "\$time_str\\"\n''')

content, n = pat.subn('', content, count=1)
with open(path, "w") as f:
    f.write(content)
print("  [ok]   removed hook from", path)
PYEOF
    fi
else
    echo "  [skip] no hook found in $ENVSETUP"
fi

BASHRC="$HOME/.bashrc"
if grep -qF "telegram-build-notifier" "$BASHRC" 2>/dev/null; then
    grep -vF "telegram-build-notifier" "$BASHRC" > "$BASHRC.tmp" && mv "$BASHRC.tmp" "$BASHRC"
    echo "  [ok]   removed source line from $BASHRC"
else
    echo "  [skip] $BASHRC not configured"
fi

echo "== done =="
echo "Config file left at: $HOME/.config/telegram-build-notifier.env"
echo "Repo left at:        $REPO_DIR"