# Telegram Build Notifier

Reusable Telegram build notifications for **any** Android ROM build (LineageOS, ArrowOS,
PixelExperience, EvolutionX, AOSP, ...). On success it sends your banner image + ROM details
+ an SCP download command; on failure it sends the error log excerpt.

It hooks into the shared AOSP `build/make/envsetup.sh` (`_wrap_build`), which is identical
across all AOSP-based ROMs — so the **same** notifier works on every ROM you build.

## Features

- ✅ / ❌ success / failure notifications with build duration
- 🖼 Sends a banner image (e.g. `image.png`) on success
- 📦 ROM zip name, size and device on success
- ⬇ Copy-paste `scp` download command (works from your local PC)
- 📄 Last 15 lines of `out/error.log` on failure (MarkdownV2 code block)
- Two integration modes (wrapper survives `repo sync`; auto-hook does not)

## Installation

```bash
git clone https://github.com/YOUR_USER/telegram-build-notifier.git ~/telegram-build-notifier
cd ~/telegram-build-notifier
./install.sh /path/to/your/rom/tree
```

For multiple ROMs, run `./install.sh` once per ROM root:

```bash
./install.sh ~/android/lineage
./install.sh ~/android/RMX2020   # ArrowOS, etc.
```

Then configure the bot:

```bash
nano ~/.config/telegram-build-notifier.env
```

```bash
export TELEGRAM_BOT_TOKEN="123456:ABC-DEF..."
export TELEGRAM_CHAT_ID="5412335559"
export SERVER_IP="1.2.3.4"          # your build server's public IP
export SSH_USER="fahad"             # ssh user on the build server
export BANNER_IMAGE="image.png"     # banner placed in the ROM root
```

Finally load it:

```bash
source ~/.bashrc      # bash
source ~/.zshrc       # zsh
```

> install.sh configures **both** `~/.bashrc` and `~/.zshrc` (whichever exists),
> so the notifier works no matter which shell you use.

## Usage

### Mode 1 — Auto-hook (default after install.sh)

The installer patches `build/make/envsetup.sh` `_wrap_build()`, so **every** build command
(`m`, `mka`, `mm`, `make`, `brunch`, ...) sends a notification automatically:

```bash
source build/envsetup.sh
lunch lineage_RMX3191-eng
mka bacon
```

> ⚠️ `build/` is wiped by `repo sync`. After syncing, re-run `./install.sh <rom_root>`.
> Your config is kept; the re-run is idempotent.

### Mode 2 — Wrapper (survives `repo sync`, zero ROM edits)

Instead of the auto-hook, prefix any build command with `notify-build`:

```bash
source build/envsetup.sh
lunch lineage_RMX3191-eng
notify-build mka bacon
```

This mode never touches your ROM tree, so `repo sync` cannot break it.

### Sending a test notification

```bash
source ~/telegram-build-notifier/telegram-notify.sh
send_build_notification 0 "01:30:00"   # fake success
send_build_notification 1 "00:05:00"   # fake failure
```

## Configuration reference

| Variable | Required | Purpose |
|----------|----------|---------|
| `TELEGRAM_BOT_TOKEN` | yes | Bot token from @BotFather |
| `TELEGRAM_CHAT_ID` | yes | Chat/group to notify |
| `SERVER_IP` | no | Enables SCP download command on success |
| `SSH_USER` | no | SSH user in the SCP command |
| `BANNER_IMAGE` | no | Path (absolute or ROM-relative) to banner image; defaults to `<ROM root>/image.png` |
| `PRODUCT_PREFIX` | no | Prefix stripped from `TARGET_PRODUCT`; default `lineage_` |
| `ZIP_PATTERN` | no | Glob for the flashable zip in `$OUT`; default `lineage-*.zip` |

Non-LineageOS ROMs: set `PRODUCT_PREFIX` and `ZIP_PATTERN` to match, e.g. for ArrowOS
`PRODUCT_PREFIX="arrow_"` and `ZIP_PATTERN="arrow-*.zip"`.

## Uninstall

```bash
./uninstall.sh /path/to/your/rom/tree
```

Restores `build/make/envsetup.sh` (from a backup) and removes the shell rc entry.
The config file and repo folder are kept.

## License

MIT