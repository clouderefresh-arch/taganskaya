#!/usr/bin/env bash
#
# convert_one.sh
#
# Тонкий враппер: конвертирует ровно ОДИН .360 файл через GoPro Player.
# Удобно встраивать в существующие скрипты автозагрузки — после того
# как скрипт загрузил очередной файл, вызывайте:
#
#     /path/to/taganskaya/scripts/convert_one.sh "/path/to/clip.360"
#
# Под капотом — это просто batch_convert_360.sh с одним входом и
# дефолтами, удобными для интеграции (--quiet --json).
#
# Поддерживаются те же ENV-переменные:
#   GOPRO360_OUTPUT     — куда GoPro Player пишет mp4 (по умолчанию ~/Movies/GoPro)
#   GOPRO360_MOVE       — куда переносить исходник после успеха
#                         (по умолчанию <папка_исходника>/_processed)
#   GOPRO360_NO_MOVE=1  — не переносить исходник
#   GOPRO360_TIMEOUT    — таймаут ожидания mp4 в секундах (по умолчанию 14400)
#   GOPRO360_QUIET=0    — включить вывод прогресса в stderr
#   GOPRO360_NO_JSON=1  — не печатать JSON в stdout
#
# Exit-коды совпадают с batch_convert_360.sh.

set -uo pipefail

if [[ $# -lt 1 ]]; then
	echo "Использование: $0 <файл.360>" >&2
	exit 12
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BATCH="$SCRIPT_DIR/batch_convert_360.sh"

INPUT="$1"
if [[ ! -f "$INPUT" ]]; then
	echo "Файл не найден: $INPUT" >&2
	exit 12
fi

declare -a ARGS=()
ARGS+=(--output "${GOPRO360_OUTPUT:-${HOME}/Movies/GoPro}")
ARGS+=(--timeout "${GOPRO360_TIMEOUT:-14400}")

if [[ -n "${GOPRO360_MOVE:-}" ]]; then
	ARGS+=(--move "$GOPRO360_MOVE")
fi
if [[ "${GOPRO360_NO_MOVE:-0}" == "1" ]]; then
	ARGS+=(--no-move)
fi
if [[ "${GOPRO360_QUIET:-1}" == "1" ]]; then
	ARGS+=(--quiet)
fi
if [[ "${GOPRO360_NO_JSON:-0}" != "1" ]]; then
	ARGS+=(--json)
fi

exec "$BATCH" "${ARGS[@]}" "$INPUT"
