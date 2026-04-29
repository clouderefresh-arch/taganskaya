#!/usr/bin/env bash
#
# watch_folder.sh
#
# Запускается launchd-агентом каждый раз, когда в "горячей" папке
# появляется новый файл. Запускает batch_convert_360.sh для конвертации.
#
# Использование:
#   watch_folder.sh <горячая_папка> [папка_для_mp4] [папка_для_исходников]
#
# Не предназначен для интерактивного запуска — обычно его дёргает
# launchd через WatchPaths (см. com.user.gopro360batch.plist).

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BATCH="$SCRIPT_DIR/batch_convert_360.sh"

WATCH_DIR="${1:-${HOME}/Movies/GoPro_INBOX}"
OUT_DIR="${2:-${HOME}/Movies/GoPro}"
DONE_DIR="${3:-${HOME}/Movies/GoPro_PROCESSED}"

LOCK="/tmp/gopro360-batch.lock"

# Не запускаем второй экземпляр параллельно
exec 9>"$LOCK"
if ! flock -n 9; then
	echo "Уже идёт пакетная конвертация — выхожу" >&2
	exit 0
fi

# Даём 30 секунд на дозапись файлов в папку (вдруг копирование ещё идёт)
sleep 30

# Проверяем, есть ли вообще .360 файлы
shopt -s nullglob
files=("$WATCH_DIR"/*.360 "$WATCH_DIR"/*.[36]60)
shopt -u nullglob
if [[ ${#files[@]} -eq 0 ]]; then
	exit 0
fi

mkdir -p "$OUT_DIR" "$DONE_DIR"

"$BATCH" --output "$OUT_DIR" --move "$DONE_DIR" "$WATCH_DIR"
