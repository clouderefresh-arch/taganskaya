#!/usr/bin/env bash
#
# batch_convert_360.sh
#
# Пакетная конвертация .360 → .mp4 через GoPro Player.
# Скрипт находит все .360 файлы в одной или нескольких папках,
# по очереди добавляет их в очередь экспорта GoPro Player'а,
# затем запускает очередь и (опционально) ждёт появления mp4-файлов
# в папке назначения, помечая исходники как обработанные.
#
# Использование:
#   ./batch_convert_360.sh [опции] <папка1> [папка2 ...]
#
# Опции:
#   -o, --output <dir>    Папка, куда GoPro Player сохраняет mp4
#                         (по умолчанию ~/Movies/GoPro). Используется
#                         только для проверки, что mp4 действительно
#                         появился, и для перемещения исходников.
#   -m, --move <dir>      Куда перемещать .360 после успешного экспорта
#                         (по умолчанию <папка_исходника>/_processed).
#   -r, --recursive       Рекурсивно искать .360 файлы во всех подпапках.
#   -n, --dry-run         Только показать план без реального запуска.
#   --no-start            Не запускать очередь автоматически (только
#                         наполнить её и выйти).
#   --no-wait             Не ждать завершения экспорта (не перемещать
#                         исходники).
#   -h, --help            Показать эту справку.
#
# Требования (macOS):
#   * GoPro Player установлен.
#   * Один раз вручную выставлены настройки экспорта (Разрешение, Кодек,
#     Качество, AntiShake и т.д.) — GoPro Player запоминает их между
#     запусками.
#   * Терминалу выдано разрешение
#     System Settings → Privacy & Security → Accessibility.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EXPORT_AS="$SCRIPT_DIR/export_360.applescript"
START_AS="$SCRIPT_DIR/start_queue.applescript"
LOG_DIR="${HOME}/Library/Logs/gopro-360-batch"
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/batch-$(date +%Y%m%d-%H%M%S).log"

OUTPUT_DIR="${HOME}/Movies/GoPro"
MOVE_DIR=""
RECURSIVE=0
DRY_RUN=0
START_QUEUE=1
WAIT_RESULTS=1

log() {
	local msg="[$(date '+%Y-%m-%d %H:%M:%S')] $*"
	echo "$msg" | tee -a "$LOG_FILE" >&2
}

die() {
	log "ОШИБКА: $*"
	exit 1
}

usage() {
	sed -n '2,40p' "$0" | sed 's/^# \{0,1\}//'
	exit 0
}

while [[ $# -gt 0 ]]; do
	case "$1" in
		-o|--output)   OUTPUT_DIR="$2"; shift 2;;
		-m|--move)     MOVE_DIR="$2"; shift 2;;
		-r|--recursive) RECURSIVE=1; shift;;
		-n|--dry-run)  DRY_RUN=1; shift;;
		--no-start)    START_QUEUE=0; shift;;
		--no-wait)     WAIT_RESULTS=0; shift;;
		-h|--help)     usage;;
		--)            shift; break;;
		-*)            die "Неизвестная опция: $1";;
		*)             break;;
	esac
done

[[ $# -ge 1 ]] || die "Не указана ни одна папка с .360 файлами. См. --help"

if [[ "$(uname -s)" != "Darwin" ]]; then
	log "ВНИМАНИЕ: скрипт рассчитан на macOS (GoPro Player)."
fi

if [[ ! -d "/Applications/GoPro Player.app" && ! -d "/Applications/GoPro Player Beta.app" ]]; then
	log "ВНИМАНИЕ: GoPro Player.app не найден в /Applications. Продолжаю на свой страх и риск."
fi

collect_files() {
	local dir="$1"
	if [[ $RECURSIVE -eq 1 ]]; then
		find "$dir" -type f \( -iname '*.360' \) ! -path '*/_processed/*' -print0
	else
		find "$dir" -maxdepth 1 -type f \( -iname '*.360' \) -print0
	fi
}

declare -a ALL_FILES=()
for d in "$@"; do
	[[ -d "$d" ]] || { log "Пропускаю: $d не папка"; continue; }
	while IFS= read -r -d '' f; do
		ALL_FILES+=("$f")
	done < <(collect_files "$d")
done

TOTAL=${#ALL_FILES[@]}
if [[ $TOTAL -eq 0 ]]; then
	log "Не найдено .360 файлов. Выходим."
	exit 0
fi

log "Найдено .360 файлов: $TOTAL"
for f in "${ALL_FILES[@]}"; do
	log "  • $f"
done

if [[ $DRY_RUN -eq 1 ]]; then
	log "Dry-run: выходим без запуска GoPro Player."
	exit 0
fi

QUEUED=()
FAILED=()

for f in "${ALL_FILES[@]}"; do
	log "Добавляю в очередь: $f"
	if /usr/bin/osascript "$EXPORT_AS" "$f" >>"$LOG_FILE" 2>&1; then
		QUEUED+=("$f")
	else
		log "  ✗ не удалось добавить в очередь"
		FAILED+=("$f")
	fi
	# Небольшая пауза, чтобы UI успевал
	sleep 1
done

log "В очередь добавлено: ${#QUEUED[@]}, ошибок: ${#FAILED[@]}"

if [[ $START_QUEUE -eq 1 && ${#QUEUED[@]} -gt 0 ]]; then
	log "Запускаю очередь экспорта..."
	/usr/bin/osascript "$START_AS" >>"$LOG_FILE" 2>&1 || log "Не удалось автоматически запустить очередь — запустите её вручную в GoPro Player."
fi

if [[ $WAIT_RESULTS -eq 1 && ${#QUEUED[@]} -gt 0 ]]; then
	log "Ожидаю появления mp4 файлов в $OUTPUT_DIR ..."
	mkdir -p "$OUTPUT_DIR"
	for src in "${QUEUED[@]}"; do
		base="$(basename "$src")"
		stem="${base%.*}"
		expected="$OUTPUT_DIR/$stem.mp4"
		# Ждём максимум 4 часа на файл — большие 360° клипы могут
		# рендериться долго.
		for ((i=0; i<14400; i++)); do
			if [[ -f "$expected" ]]; then
				# Убеждаемся, что файл уже не растёт (запись завершена)
				size1=$(stat -f%z "$expected" 2>/dev/null || echo 0)
				sleep 5
				size2=$(stat -f%z "$expected" 2>/dev/null || echo 0)
				if [[ "$size1" == "$size2" && "$size1" -gt 0 ]]; then
					break
				fi
			fi
			sleep 1
		done

		if [[ -f "$expected" ]]; then
			log "  ✓ готово: $expected"
			# Перемещаем исходник
			target_dir="$MOVE_DIR"
			if [[ -z "$target_dir" ]]; then
				target_dir="$(dirname "$src")/_processed"
			fi
			mkdir -p "$target_dir"
			mv -n "$src" "$target_dir/" && log "    → исходник перемещён в $target_dir"
		else
			log "  ✗ не дождался mp4 для $src"
			FAILED+=("$src")
		fi
	done
fi

log "ГОТОВО. Успехов: $((${#QUEUED[@]} - 0)) (с учётом возможных таймаутов: см. лог), ошибок: ${#FAILED[@]}"
log "Полный лог: $LOG_FILE"

if [[ ${#FAILED[@]} -gt 0 ]]; then
	exit 2
fi
