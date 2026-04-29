-- start_queue.applescript
--
-- После того как все .360 файлы добавлены в очередь экспорта,
-- этот скрипт открывает окно очереди и запускает экспорт.
--
-- Использование:
--   osascript scripts/start_queue.applescript

tell application "GoPro Player" to activate
delay 1

tell application "System Events"
	tell process "GoPro Player"
		set frontmost to true

		-- Открываем окно очереди экспорта через меню Window
		try
			click menu item "Export Queue" of menu 1 of menu bar item "Window" of menu bar 1
		on error
			try
				click menu item "Очередь экспорта" of menu 1 of menu bar item "Окно" of menu bar 1
			end try
		end try

		delay 1

		-- Ищем окно очереди и нажимаем "Start" / "Начать"
		repeat with w in windows
			set wname to ""
			try
				set wname to name of w
			end try
			if wname contains "Queue" or wname contains "Очередь" then
				repeat with btn in (buttons of w)
					set btnName to ""
					try
						set btnName to name of btn
					end try
					if btnName is in {"Start", "Начать", "Start All", "Начать все", "Запустить"} then
						click btn
						return "queue started"
					end if
				end repeat
			end if
		end repeat
	end tell
end tell

return "queue window not found or already running"
