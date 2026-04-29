#!/usr/bin/env bash
#
# install_launchd.sh — устанавливает или удаляет launchd-агента,
# который сторожит папку INBOX и запускает batch_convert_360.sh.
#
# Использование:
#   ./install_launchd.sh install <INBOX> [<OUTPUT>] [<PROCESSED>]
#   ./install_launchd.sh uninstall

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
PLIST_SRC="$REPO_DIR/launchd/com.user.gopro360batch.plist"
PLIST_DST="$HOME/Library/LaunchAgents/com.user.gopro360batch.plist"
LABEL="com.user.gopro360batch"

action="${1:-}"
case "$action" in
	install)
		INBOX="${2:?usage: install_launchd.sh install <INBOX> [<OUTPUT>] [<PROCESSED>]}"
		OUT="${3:-$HOME/Movies/GoPro}"
		DONE="${4:-$HOME/Movies/GoPro_PROCESSED}"

		mkdir -p "$INBOX" "$OUT" "$DONE" "$HOME/Library/LaunchAgents"

		# Нормализуем пути в абсолютные
		INBOX_ABS="$(cd "$INBOX" && pwd)"
		OUT_ABS="$(cd "$OUT" && pwd)"
		DONE_ABS="$(cd "$DONE" && pwd)"
		WATCHER="$SCRIPT_DIR/watch_folder.sh"

		cat > "$PLIST_DST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>$LABEL</string>
    <key>ProgramArguments</key>
    <array>
        <string>/bin/bash</string>
        <string>-lc</string>
        <string>"$WATCHER" "$INBOX_ABS" "$OUT_ABS" "$DONE_ABS"</string>
    </array>
    <key>WatchPaths</key>
    <array>
        <string>$INBOX_ABS</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>ThrottleInterval</key>
    <integer>60</integer>
    <key>StandardOutPath</key>
    <string>/tmp/gopro360batch.out.log</string>
    <key>StandardErrorPath</key>
    <string>/tmp/gopro360batch.err.log</string>
</dict>
</plist>
PLIST

		launchctl unload "$PLIST_DST" 2>/dev/null || true
		launchctl load   "$PLIST_DST"
		echo "Установлено: $PLIST_DST"
		echo "  INBOX:     $INBOX_ABS"
		echo "  OUTPUT:    $OUT_ABS"
		echo "  PROCESSED: $DONE_ABS"
		;;
	uninstall)
		if [[ -f "$PLIST_DST" ]]; then
			launchctl unload "$PLIST_DST" 2>/dev/null || true
			rm -f "$PLIST_DST"
			echo "Удалено: $PLIST_DST"
		else
			echo "Не установлен."
		fi
		;;
	*)
		echo "usage:"
		echo "  $0 install <INBOX> [<OUTPUT>] [<PROCESSED>]"
		echo "  $0 uninstall"
		exit 1
		;;
esac
