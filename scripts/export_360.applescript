-- export_360.applescript
--
-- Открывает один .360 файл в GoPro Player и добавляет его в очередь экспорта
-- с уже выбранными в приложении пресетами (Разрешение/Кодек/Битрейт и т.д.).
--
-- Использование:
--   osascript scripts/export_360.applescript "/полный/путь/к/файлу.360"
--
-- ВАЖНО:
--   * GoPro Player должен быть установлен.
--   * Терминал/iTerm/cron-агент должны иметь разрешение
--     System Settings → Privacy & Security → Accessibility
--     (без него UI scripting работать не будет).
--   * Настройки экспорта (4K, H.264, битрейт, AntiShake и т.п.)
--     запоминаются GoPro Player'ом между запусками — выставьте их
--     один раз вручную, потом скрипт будет использовать те же значения.

on run argv
	if (count of argv) < 1 then
		error "Не передан путь к .360 файлу" number 1001
	end if

	set inputPath to item 1 of argv
	set inputPOSIX to inputPath as text
	set inputAlias to POSIX file inputPOSIX

	-- Запускаем GoPro Player и открываем файл
	tell application "GoPro Player"
		activate
		open inputAlias
	end tell

	-- Ждём, пока приложение полностью загрузит клип
	delay 4

	tell application "System Events"
		tell process "GoPro Player"
			set frontmost to true

			-- Открываем диалог экспорта: File → Export… (⌘E)
			keystroke "e" using {command down}

			-- Ждём появления окна "Настройки экспорта" / "Export Settings"
			set exportWindow to my waitForExportSheet(15)

			if exportWindow is missing value then
				error "Не удалось дождаться окна экспорта" number 1002
			end if

			-- Нажимаем "Отправить в очередь" / "Add to Queue".
			-- В разных локализациях кнопка называется по-разному, поэтому
			-- ищем её по нескольким возможным заголовкам.
			set queueButton to my findButton(exportWindow, {"Отправить в очередь", "Add to Queue", "Add To Queue", "В очередь"})

			if queueButton is missing value then
				error "Не найдена кнопка 'Отправить в очередь'" number 1003
			end if

			click queueButton

			-- Небольшая пауза, чтобы окно экспорта успело закрыться,
			-- прежде чем мы закроем сам клип.
			delay 1

			-- Закрываем открытый документ (⌘W), чтобы освободить память
			keystroke "w" using {command down}
			delay 0.5

			-- Если появился диалог "Сохранить изменения?" — отвечаем "Не сохранять"
			try
				if exists sheet 1 of front window then
					set savePrompt to sheet 1 of front window
					set dontSaveBtn to my findButton(savePrompt, {"Don't Save", "Не сохранять", "Удалить", "Discard"})
					if dontSaveBtn is not missing value then
						click dontSaveBtn
					end if
				end if
			end try
		end tell
	end tell

	return "queued: " & inputPOSIX
end run

-- Ждёт появления листа/окна экспорта и возвращает его UI элемент
on waitForExportSheet(timeoutSeconds)
	set deadline to (current date) + timeoutSeconds
	repeat while (current date) < deadline
		tell application "System Events"
			tell process "GoPro Player"
				try
					set theWindow to front window
					-- Окно экспорта обычно открывается как sheet поверх главного окна
					if exists sheet 1 of theWindow then
						return sheet 1 of theWindow
					end if
					-- Иногда экспорт — это отдельное окно
					repeat with w in windows
						set wname to ""
						try
							set wname to name of w
						end try
						if wname contains "Export" or wname contains "Экспорт" or wname contains "Настройки экспорта" then
							return w
						end if
					end repeat
				end try
			end tell
		end tell
		delay 0.3
	end repeat
	return missing value
end waitForExportSheet

-- Ищет кнопку с одним из указанных заголовков в данном UI-элементе
on findButton(uiElement, possibleNames)
	tell application "System Events"
		try
			repeat with btn in (buttons of uiElement)
				set btnName to ""
				try
					set btnName to name of btn
				end try
				repeat with candidate in possibleNames
					if btnName is (candidate as text) then
						return btn
					end if
				end repeat
			end repeat
		end try
	end tell
	return missing value
end findButton
