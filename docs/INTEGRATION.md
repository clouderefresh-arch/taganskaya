# Интеграция в существующий скрипт автозагрузки

Этот документ — практические рецепты для встраивания конвертации
`.360 → mp4` в ваш текущий процесс автозагрузки видео с GoPro/SD-карты.

## Что вы получаете

Два готовых entry-point'а:

- `scripts/convert_one.sh <файл.360>` — обработать **один** файл.
  Удобно вызывать сразу после того, как ваш загрузчик скачал
  очередной клип. Печатает JSON-итог в stdout.
- `scripts/batch_convert_360.sh [опции] <пути...>` — пакетная
  обработка папок/файлов.

Стабильные exit-коды:

| Код | Значение |
|-----|----------|
| 0   | Успех (или нечего делать) |
| 2   | Часть файлов не сконвертирована |
| 10  | Не macOS |
| 11  | Не найден GoPro Player / osascript |
| 12  | Не указаны входные пути / файл не найден |
| 13  | Уже идёт другой инстанс (flock) |

## Глобальные правила

1. **GoPro Player один на систему** — нельзя запускать две конвертации
   параллельно. Скрипт по умолчанию защищён `flock`'ом
   (`/tmp/gopro360-batch.lock`), повторный вызов вернёт код 13.
2. **Вызов синхронный** (блокирующий): функция возвращается, когда mp4
   действительно лежит в `--output` (или истёк `--timeout`).
3. **Перед стартом проверьте предусловия** один раз:
   `scripts/batch_convert_360.sh --check` (вернёт 0, 10 или 11).
4. Во время конвертации не трогать мышь и клавиатуру (UI scripting).

---

## Рецепт 1. Покадровая интеграция (рекомендуется)

Самый простой и надёжный путь — после каждого скачанного файла
вызывать `convert_one.sh`. Конвертация одного клипа короткая, ошибки
изолированы.

```bash
# где-то в начале вашего скрипта автозагрузки:
TAGANSKAYA="$HOME/taganskaya"
export GOPRO360_OUTPUT="$HOME/Movies/GoPro"
export GOPRO360_MOVE="$HOME/Movies/GoPro_360_PROCESSED"
export GOPRO360_QUIET=1     # глушим INFO-логи; ошибки пойдут в stderr

# проверка окружения один раз
if ! "$TAGANSKAYA/scripts/batch_convert_360.sh" --check; then
    echo "GoPro Player конвертер не готов — пропускаю автоконвертацию." >&2
    SKIP_CONVERT=1
fi

# ... ваш код, который скачивает файлы ...

download_file "$REMOTE" "$LOCAL_PATH"

if [[ -z "${SKIP_CONVERT:-}" && "$LOCAL_PATH" == *.360 ]]; then
    if json="$("$TAGANSKAYA/scripts/convert_one.sh" "$LOCAL_PATH")"; then
        echo "OK: $json"
    else
        rc=$?
        echo "Конвертация $LOCAL_PATH провалилась (rc=$rc): $json" >&2
        # rc=2 — ошибка по конкретному файлу, продолжаем
        # rc=10/11 — нет GoPro Player, отключаем дальнейшие попытки
        [[ $rc -ge 10 ]] && SKIP_CONVERT=1
    fi
fi
```

JSON в stdout выглядит так и легко парсится `jq`:

```json
{"total":1,"queued":1,"succeeded":1,"failed":[],"log":"/Users/me/Library/Logs/gopro-360-batch/batch-20260429-180102-12345.log"}
```

## Рецепт 2. Пакетная обработка после всей загрузки

Если вы сначала качаете всё, потом обрабатываете — в самом конце
скрипта добавьте один вызов:

```bash
"$TAGANSKAYA/scripts/batch_convert_360.sh" \
    --recursive \
    --quiet \
    --json \
    --output "$HOME/Movies/GoPro" \
    --move   "$HOME/Movies/GoPro_360_PROCESSED" \
    "$DOWNLOAD_DIR"
rc=$?
case "$rc" in
    0)  echo "Все .360 сконвертированы";;
    2)  echo "Часть .360 не сконвертирована, см. лог" >&2;;
    10|11) echo "GoPro Player не готов, пропускаем" >&2;;
    13) echo "Конвертер уже занят" >&2;;
    *)  echo "Неожиданная ошибка rc=$rc" >&2;;
esac
```

## Рецепт 3. Полная развязка через launchd (без правки своего скрипта)

Если вы вообще не хотите трогать существующий код — настройте
watch-folder, и любой `.360`, скинутый в INBOX, обработается сам:

```bash
~/taganskaya/scripts/install_launchd.sh install \
    "$DOWNLOAD_DIR" \
    "$HOME/Movies/GoPro" \
    "$HOME/Movies/GoPro_360_PROCESSED"
```

Ваш загрузчик уже кладёт `.360` в `$DOWNLOAD_DIR` — больше ничего
делать не нужно. Снять:

```bash
~/taganskaya/scripts/install_launchd.sh uninstall
```

---

## Переменные окружения для convert_one.sh

| Переменная | Назначение | Дефолт |
|------------|------------|--------|
| `GOPRO360_OUTPUT`  | Папка mp4 (та же, что в Preferences GoPro Player) | `~/Movies/GoPro` |
| `GOPRO360_MOVE`    | Куда переносить исходник после успеха | `<dir>/_processed` |
| `GOPRO360_NO_MOVE` | `1` — не переносить исходник | `0` |
| `GOPRO360_TIMEOUT` | Таймаут ожидания mp4 в секундах | `14400` (4 часа) |
| `GOPRO360_QUIET`   | `1` — заглушить INFO-логи | `1` |
| `GOPRO360_NO_JSON` | `1` — не печатать JSON в stdout | `0` |
| `GOPRO360_LOG_DIR` | Куда писать лог-файлы сессий | `~/Library/Logs/gopro-360-batch` |
| `GOPRO360_LOCK`    | Путь lock-файла для flock | `/tmp/gopro360-batch.lock` |

## Проверка сценария до боевого запуска

```bash
# 1) Проверить, что окружение готово
"$TAGANSKAYA/scripts/batch_convert_360.sh" --check && echo OK

# 2) Прогон без реальной конвертации — посмотреть, что найдётся
"$TAGANSKAYA/scripts/batch_convert_360.sh" --dry-run --json -r "$DOWNLOAD_DIR"

# 3) Один файл — реальный прогон
"$TAGANSKAYA/scripts/convert_one.sh" "$DOWNLOAD_DIR/GS010001.360"
```

## Парсинг JSON в bash через jq

```bash
result="$("$TAGANSKAYA/scripts/convert_one.sh" "$f")"
total=$(echo "$result"      | jq -r .total)
succeeded=$(echo "$result"  | jq -r .succeeded)
failed=$(echo "$result"     | jq -r '.failed | length')
log=$(echo "$result"        | jq -r .log)

if (( failed > 0 )); then
    echo "Не удалось сконвертировать $failed файлов. Лог: $log" >&2
fi
```

## Типовые проблемы при интеграции

- **Скрипт автозагрузки запускается из cron/launchd** — у такого
  процесса нет графического контекста и Accessibility. Решение:
  либо запускать через launchd-агент пользователя
  (`LaunchAgents`, не `LaunchDaemons`), либо триггерить уже
  залогиненную пользовательскую сессию (см. Рецепт 3).
- **Файл ещё копируется, когда вы дёргаете `convert_one.sh`** —
  убедитесь, что загрузчик завершил запись (например, ваш загрузчик
  пишет во временный файл `*.360.part` и переименовывает в `*.360`
  только после `fsync`).
- **Несколько параллельных обработок** — повторный вызов вернёт код
  13 благодаря flock. Это нормально, в скрипте обработайте отдельно.
- **mp4 не появляется в `--output`** — проверьте, что папка
  совпадает с `GoPro Player → Preferences → Export Location`.
