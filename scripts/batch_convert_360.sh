#!/usr/bin/env bash
#
# batch_convert_360.sh
#
# Пакетная конвертация .360 → .mp4 через GoPro Player.
# Скрипт находит все .360 файлы в одной или нескольких папках/файлах,
# по очереди добавляет их в очередь экспорта GoPro Player'а,
# затем запускает очередь и (опционально) ждёт появления mp4-файлов
# в папке назначения, помечая исходники как обработанные.
#
# Использование:
#   ./batch_convert_360.sh [опции] <папка_или_файл> [еще ...]
#
# Опции:
#   -o, --output <dir>    Папка, куда GoPro Player сохраняет mp4
#                         (по умолчанию ~/Movies/GoPro). Используется
#                         для проверки готовности и решения, был ли
#                         файл успешно сконвертирован.
#   -m, --move <dir>      Куда перемещать .360 после успешного экспорта
#                         (по умолчанию <папка_исходника>/_processed).
#   --no-move             Не трогать исходные .360 файлы после экспорта.
#   -r, --recursive       Рекурсивно искать .360 во всех подпапках.
#   -t, --timeout <sec>   Сколько секунд ждать готовности mp4 на один
#                         файл (по умолчанию 14400, т.е. 4 часа).
#   -n, --dry-run         Только показать план без реального запуска.
#   --no-start            Не запускать очередь автоматически (только
#                         наполнить её и выйти).
#   --no-wait             Не ждать завершения экспорта (не двигать
#                         исходники, не считать ошибкой отсутствие mp4).
#   -q, --quiet           Не выводить INFO в stderr, оставить только
#                         ошибки. Полный лог всё равно пишется в файл.
#   --json                В stdout вывести итог в JSON. Удобно для
#                         интеграции — родительский скрипт сможет
#                         распарсить total/queued/succeeded/failed.
#   --check               Только проверить предусловия (macOS, GoPro
#                         Player, пути) и выйти. Ничего не запускает.
#   --no-lock             Не брать flock (по умолчанию запуск второго
#                         инстанса параллельно блокируется).
#   -h, --help            Показать справку.
#
# Стабильные exit-коды (для встраивания в автозагрузку):
#   0  — всё успешно сконвертировано (или нечего было делать).
#   2  — часть файлов не сконвертирована (см. лог и --json).
#   10 — не macOS.
#   11 — не найден GoPro Player.
#   12 — не указаны входные пути.
#   13 — уже идёт другой инстанс конвертации (flock).
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
LOG_DIR="${GOPRO360_LOG_DIR:-${HOME}/Library/Logs/gopro-360-batch}"
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/batch-$(date +%Y%m%d-%H%M%S)-$$.log"
LOCK_FILE="${GOPRO360_LOCK:-/tmp/gopro360-batch.lock}"

OUTPUT_DIR="${HOME}/Movies/GoPro"
MOVE_DIR=""
NO_MOVE=0
RECURSIVE=0
DRY_RUN=0
START_QUEUE=1
WAIT_RESULTS=1
QUIET=0
JSON_OUT=0
CHECK_ONLY=0
USE_LOCK=1
WAIT_TIMEOUT=14400

log() {
	local msg="[$(date '+%Y-%m-%d %H:%M:%S')] $*"
	echo "$msg" >>"$LOG_FILE"
	if [[ $QUIET -eq 0 ]]; then
		echo "$msg" >&2
	fi
}

err() {
	local msg="[$(date '+%Y-%m-%d %H:%M:%S')] ОШИБКА: $*"
	echo "$msg" >>"$LOG_FILE"
	echo "$msg" >&2
}

die() {
	local code="${1:-1}"; shift || true
	err "$*"
	exit "$code"
}

usage() {
	sed -n '2,70p' "$0" | sed 's/^# \{0,1\}//'
	exit 0
}

while [[ $# -gt 0 ]]; do
	case "$1" in
		-o|--output)    OUTPUT_DIR="$2"; shift 2;;
		-m|--move)      MOVE_DIR="$2"; shift 2;;
		--no-move)      NO_MOVE=1; shift;;
		-r|--recursive) RECURSIVE=1; shift;;
		-t|--timeout)   WAIT_TIMEOUT="$2"; shift 2;;
		-n|--dry-run)   DRY_RUN=1; shift;;
		--no-start)     START_QUEUE=0; shift;;
		--no-wait)      WAIT_RESULTS=0; shift;;
		-q|--quiet)     QUIET=1; shift;;
		--json)         JSON_OUT=1; shift;;
		--check)        CHECK_ONLY=1; shift;;
		--no-lock)      USE_LOCK=0; shift;;
		-h|--help)      usage;;
		--)             shift; break;;
		-*)             die 1 "Неизвестная опция: $1";;
		*)              break;;
	esac
done

check_preconditions() {
	if [[ "$(uname -s)" != "Darwin" ]]; then
		err "Скрипт работает только на macOS (GoPro Player). uname=$(uname -s)"
		return 10
	fi

	if [[ ! -d "/Applications/GoPro Player.app" && ! -d "/Applications/GoPro Player Beta.app" ]]; then
		err "Не найден GoPro Player.app в /Applications. Установите GoPro Player с https://gopro.com/."
		return 11
	fi

	if [[ ! -x /usr/bin/osascript ]]; then
		err "/usr/bin/osascript недоступен."
		return 11
	fi

	for f in "$EXPORT_AS" "$START_AS"; do
		if [[ ! -f "$f" ]]; then
			err "Не найден AppleScript: $f"
			return 11
		fi
	done

	return 0
}

if [[ $CHECK_ONLY -eq 1 ]]; then
	rc=0
	check_preconditions || rc=$?
	if [[ $rc -eq 0 ]]; then
		log "Проверка предусловий: OK"
	fi
	exit "$rc"
fi

if [[ $# -lt 1 ]]; then
	die 12 "Не указаны входные пути (.360 файлы или папки). См. --help"
fi

if [[ $DRY_RUN -eq 0 ]]; then
	check_preconditions
	pre_rc=$?
	if [[ $pre_rc -ne 0 ]]; then
		exit "$pre_rc"
	fi
fi

if [[ $USE_LOCK -eq 1 && $DRY_RUN -eq 0 ]]; then
	exec 9>"$LOCK_FILE"
	if ! flock -n 9; then
		die 13 "Уже запущен другой инстанс конвертации (lock: $LOCK_FILE). Используйте --no-lock, если уверены."
	fi
fi

collect_files() {
	local p="$1"
	if [[ -f "$p" ]]; then
		case "$p" in
			*.360|*.[36]60)
				printf '%s\0' "$p"
				;;
		esac
		return
	fi
	if [[ ! -d "$p" ]]; then
		log "Пропускаю: $p не папка и не файл"
		return
	fi
	if [[ $RECURSIVE -eq 1 ]]; then
		find "$p" -type f -iname '*.360' ! -path '*/_processed/*' -print0
	else
		find "$p" -maxdepth 1 -type f -iname '*.360' -print0
	fi
}

declare -a ALL_FILES=()
for arg in "$@"; do
	while IFS= read -r -d '' f; do
		ALL_FILES+=("$f")
	done < <(collect_files "$arg")
done

TOTAL=${#ALL_FILES[@]}

emit_json() {
	local total="$1" queued="$2" succeeded="$3" failed_list="$4"
	if [[ $JSON_OUT -eq 1 ]]; then
		printf '{"total":%d,"queued":%d,"succeeded":%d,"failed":[%s],"log":"%s"}\n' \
			"$total" "$queued" "$succeeded" "$failed_list" "$LOG_FILE"
	fi
}

if [[ $TOTAL -eq 0 ]]; then
	log "Не найдено .360 файлов. Выходим."
	emit_json 0 0 0 ""
	exit 0
fi

log "Найдено .360 файлов: $TOTAL"
for f in "${ALL_FILES[@]}"; do
	log "  • $f"
done

if [[ $DRY_RUN -eq 1 ]]; then
	log "Dry-run: выходим без запуска GoPro Player."
	emit_json "$TOTAL" 0 0 ""
	exit 0
fi

declare -a QUEUED=()
declare -a FAILED=()

for f in "${ALL_FILES[@]}"; do
	log "Добавляю в очередь: $f"
	if /usr/bin/osascript "$EXPORT_AS" "$f" >>"$LOG_FILE" 2>&1; then
		QUEUED+=("$f")
	else
		err "  ✗ не удалось добавить в очередь: $f"
		FAILED+=("$f")
	fi
	sleep 1
done

log "В очередь добавлено: ${#QUEUED[@]}, ошибок: ${#FAILED[@]}"

if [[ $START_QUEUE -eq 1 && ${#QUEUED[@]} -gt 0 ]]; then
	log "Запускаю очередь экспорта..."
	if ! /usr/bin/osascript "$START_AS" >>"$LOG_FILE" 2>&1; then
		err "Не удалось автоматически запустить очередь — запустите её вручную в GoPro Player."
	fi
fi

declare -a SUCCEEDED=()

if [[ $WAIT_RESULTS -eq 1 && ${#QUEUED[@]} -gt 0 ]]; then
	log "Ожидаю появления mp4 файлов в $OUTPUT_DIR (таймаут на файл: ${WAIT_TIMEOUT}s)..."
	mkdir -p "$OUTPUT_DIR"
	for src in "${QUEUED[@]}"; do
		base="$(basename "$src")"
		stem="${base%.*}"
		expected="$OUTPUT_DIR/$stem.mp4"

		i=0
		while (( i < WAIT_TIMEOUT )); do
			if [[ -f "$expected" ]]; then
				size1=$(stat -f%z "$expected" 2>/dev/null || echo 0)
				sleep 5
				size2=$(stat -f%z "$expected" 2>/dev/null || echo 0)
				if [[ "$size1" == "$size2" && "$size1" -gt 0 ]]; then
					break
				fi
				i=$((i + 5))
			fi
			sleep 1
			i=$((i + 1))
		done

		if [[ -f "$expected" ]]; then
			log "  ✓ готово: $expected"
			SUCCEEDED+=("$src")
			if [[ $NO_MOVE -eq 0 ]]; then
				target_dir="$MOVE_DIR"
				if [[ -z "$target_dir" ]]; then
					target_dir="$(dirname "$src")/_processed"
				fi
				mkdir -p "$target_dir"
				if mv -n "$src" "$target_dir/"; then
					log "    → исходник перемещён в $target_dir"
				else
					err "    → не удалось переместить $src в $target_dir"
				fi
			fi
		else
			err "  ✗ не дождался mp4 для $src"
			FAILED+=("$src")
		fi
	done
else
	if [[ $WAIT_RESULTS -eq 0 ]]; then
		# Без --wait считаем успехом всё, что попало в очередь
		SUCCEEDED=("${QUEUED[@]}")
	fi
fi

failed_json=""
sep=""
for f in "${FAILED[@]:-}"; do
	[[ -z "$f" ]] && continue
	esc=${f//\\/\\\\}
	esc=${esc//\"/\\\"}
	failed_json+="${sep}\"${esc}\""
	sep=","
done

log "ИТОГ: total=$TOTAL queued=${#QUEUED[@]} succeeded=${#SUCCEEDED[@]} failed=${#FAILED[@]}"
log "Полный лог: $LOG_FILE"

emit_json "$TOTAL" "${#QUEUED[@]}" "${#SUCCEEDED[@]}" "$failed_json"

if [[ ${#FAILED[@]} -gt 0 ]]; then
	exit 2
fi
exit 0
