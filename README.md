# taganskaya — автоматизация конвертации .360 → mp4 через GoPro Player

Набор скриптов для пакетной конвертации файлов **GoPro `.360`** в `.mp4`
с помощью **GoPro Player** на macOS — без переключения вручную между
файлами и без ручного нажатия «Экспорт» каждый раз.

## Что умеет

- Рекурсивно находит все `.360` файлы в указанных папках.
- Поочерёдно открывает каждый клип в GoPro Player и нажимает
  **«Отправить в очередь»** (`Add to Queue`) с уже выставленными вами
  настройками экспорта (разрешение, кодек, битрейт, AntiShake, Линия
  горизонта и т.д.).
- Запускает очередь экспорта.
- Ждёт, пока mp4 действительно появится в папке назначения, после чего
  переносит исходный `.360` в подпапку `_processed` (чтобы повторно его
  не обрабатывать).
- Подробный лог каждой сессии в `~/Library/Logs/gopro-360-batch/`.
- Опциональный launchd-агент: как только вы скидываете новые `.360`
  файлы в «горячую» папку (например, после слива с камеры), конвертация
  стартует сама.

## Почему так, а не FFmpeg

GoPro `.360` — это контейнер с двумя HEVC-потоками плюс CMOR-метаданные
ориентации (EAC, гиро, AntiShake). FFmpeg «как есть» эти потоки в
эквиректангуляр конвертировать **не умеет** — нужны проприетарные
шейдеры GoPro. Поэтому единственный надёжный способ получить настоящий
ровный mp4 — это GoPro Player. У него нет официального CLI, но
встроенная функция **Export Queue** прекрасно автоматизируется через
AppleScript UI scripting.

## Структура репозитория

```
scripts/
  batch_convert_360.sh       # основной CLI: пакетная обработка папок
  convert_one.sh             # враппер «один файл» для интеграции
  export_360.applescript     # добавляет один .360 в очередь экспорта
  start_queue.applescript    # запускает очередь
  watch_folder.sh            # обёртка для launchd
  install_launchd.sh         # install/uninstall launchd-агента
launchd/
  com.user.gopro360batch.plist  # шаблон launchd-агента (watch folder)
docs/
  INTEGRATION.md             # как встроить в свой скрипт автозагрузки
  TROUBLESHOOTING.md         # типовые проблемы и решения
```

## Требования

- macOS (проверено на Sonoma/Sequoia).
- Установленный **GoPro Player** (`/Applications/GoPro Player.app`).
- Bash 4+ (стандартный `/bin/bash` подойдёт).
- Разрешение **Accessibility** для терминала, из которого вы запускаете
  скрипт (см. ниже).

## Однократная настройка

### 1. Откройте GoPro Player и выставьте нужные настройки экспорта

Откройте любой `.360` файл, нажмите **Экспорт…** и в окне «Настройки
экспорта» выставьте всё как на вашем скриншоте:

- **Разрешение:** 4K
- **Кодек:** H.264 (или HEVC / ProRes по желанию)
- **Скорость экспорта**, **Качество**, **Размер файла** — на свой вкус
- **Линия горизонта**, **AntiShake** — включены
- **Битрейт**, **Denoise** — по необходимости

GoPro Player **запоминает эти настройки между запусками**, поэтому
дальше скрипту не нужно их трогать — он только нажимает «Отправить в
очередь».

### 2. Дайте Accessibility-разрешение

`System Settings` → `Privacy & Security` → `Accessibility` → добавьте
ваш терминал (`Terminal.app`, `iTerm.app`) **и** `osascript`. Без этого
UI scripting упадёт с `1002` / `1003`.

### 3. Клонируйте репозиторий

```bash
git clone <url> ~/taganskaya
cd ~/taganskaya
chmod +x scripts/*.sh
```

## Использование

### Однократный пакет

Допустим, у вас есть папка `~/Desktop/GoProDay1` с десятками `.360`
файлов:

```bash
~/taganskaya/scripts/batch_convert_360.sh ~/Desktop/GoProDay1
```

С рекурсией, своей папкой назначения и своей папкой для обработанных
исходников:

```bash
~/taganskaya/scripts/batch_convert_360.sh \
  --recursive \
  --output  ~/Movies/GoPro \
  --move    ~/Movies/GoPro_DONE \
  ~/Desktop/GoProDay1 ~/Desktop/GoProDay2
```

### Все опции

```
-o, --output <dir>   куда GoPro Player пишет mp4 (по умолчанию ~/Movies/GoPro)
-m, --move <dir>     куда переносить .360 после успешного экспорта
                     (по умолчанию <папка_исходника>/_processed)
-r, --recursive      рекурсивно обходить подпапки
-n, --dry-run        только показать список найденных файлов
--no-start           заполнить очередь и не запускать её
--no-wait            не ждать готовности mp4, не двигать исходники
-h, --help           справка
```

### Что произойдёт

1. Скрипт находит все `.360` файлы.
2. Для каждого файла:
   - запускает GoPro Player (если не запущен),
   - открывает файл (`⌘O`),
   - открывает диалог экспорта (`⌘E`),
   - нажимает **«Отправить в очередь»**,
   - закрывает документ.
3. Когда все файлы в очереди — открывает окно **Export Queue** и
   нажимает **Start**.
4. Ждёт появления mp4 в папке назначения, после чего перемещает
   исходник в `_processed`.

Полный лог пишется в
`~/Library/Logs/gopro-360-batch/batch-YYYYMMDD-HHMMSS.log`.

## Авто-режим (watch folder)

Если у вас постоянный workflow «слил с камеры → положил в папку → хочу
mp4», настройте launchd-агента.

1. Создайте «горячую» папку, куда будете сваливать новые `.360`:
   ```bash
   mkdir -p ~/Movies/GoPro_INBOX ~/Movies/GoPro ~/Movies/GoPro_PROCESSED
   ```
2. Отредактируйте `launchd/com.user.gopro360batch.plist`:
   - в `ProgramArguments` поправьте путь к `watch_folder.sh`,
   - в `WatchPaths` укажите **абсолютный** путь к `GoPro_INBOX`
     (`~` в plist не раскрывается).
3. Установите агента — проще всего одной командой:
   ```bash
   ./scripts/install_launchd.sh install \
       ~/Movies/GoPro_INBOX \
       ~/Movies/GoPro \
       ~/Movies/GoPro_PROCESSED
   ```
   (скрипт сам сгенерирует plist с абсолютными путями и загрузит его).
   Или вручную:
   ```bash
   cp launchd/com.user.gopro360batch.plist ~/Library/LaunchAgents/
   launchctl unload ~/Library/LaunchAgents/com.user.gopro360batch.plist 2>/dev/null
   launchctl load   ~/Library/LaunchAgents/com.user.gopro360batch.plist
   ```
4. Скиньте `.360` файлы в `~/Movies/GoPro_INBOX` — конвертация
   стартанёт сама через ~30 секунд (даём время на докопирование).

Логи агента: `/tmp/gopro360batch.out.log`, `/tmp/gopro360batch.err.log`.

Снять агента:

```bash
./scripts/install_launchd.sh uninstall
```

## Интеграция в чужой скрипт автозагрузки

Если у вас уже есть скрипт, который скачивает файлы с камеры/SD-карты —
готовые рецепты для встраивания конвертации (включая покадровый режим
через `convert_one.sh`, JSON-итог и стабильные exit-коды) в
[`docs/INTEGRATION.md`](docs/INTEGRATION.md).

Коротко:

```bash
# один файл — из существующего скрипта автозагрузки
~/taganskaya/scripts/convert_one.sh "$LOCAL_PATH"

# проверить, что GoPro Player и разрешения в порядке
~/taganskaya/scripts/batch_convert_360.sh --check
```

## Частые проблемы

| Симптом | Причина / решение |
|---|---|
| `Не найдена кнопка 'Отправить в очередь'` | Локализация GoPro Player отличается. Откройте `scripts/export_360.applescript` и допишите название кнопки в `findButton(...)`. |
| `execution error: System Events got an error: ... not allowed assistive access` | Не выдано разрешение Accessibility терминалу/`osascript`. |
| Скрипт «зависает» на 4 секунды на каждом файле | Это `delay 4` после открытия — GoPro Player должен загрузить клип. Большие файлы можно увеличить до `delay 6-8` в `export_360.applescript`. |
| mp4 не появляется в `--output` | Проверьте, куда GoPro Player реально сохраняет mp4 (Preferences → Export Location). Передайте именно эту папку через `--output`. |
| Очередь не стартует автоматически | `--no-start` или другая локализация меню Window. Откройте окно очереди вручную и нажмите Start. |

См. также `docs/TROUBLESHOOTING.md`.

## Лицензия

MIT.
