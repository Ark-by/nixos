-- ═══════════════════════════════════════════════════════════════════════════
--  КЛАВИШИ HYPRLAND  (из Ark-by/arch, ветка exp)
--  Формат:  bind("клавиши", действие, "Раздел: Описание")
--  Описание попадает в окно справки (SUPER+F1) — вернём, когда будет waybar.
-- =====================================================================
local mainMod     = "SUPER"
local terminal    = "kitty"
local fileManager = "kitty -e yazi"
local browser     = "firefox"

local function bind(keys, dispatcher, description, flags)
    flags = flags or {}
    if description then flags.description = description end
    if next(flags) then
        hl.bind(keys, dispatcher, flags)
    else
        hl.bind(keys, dispatcher)
    end
end

-- Система
bind(mainMod .. " + escape",
     hl.dsp.exec_cmd("command -v hyprshutdown >/dev/null 2>&1 && hyprshutdown || hyprctl dispatch exit"),
     "Система: Выйти из сессии")

-- Приложения
bind(mainMod .. " + Q", hl.dsp.exec_cmd(terminal),    "Приложения: Терминал")
bind(mainMod .. " + B", hl.dsp.exec_cmd(browser),     "Приложения: Браузер")
bind(mainMod .. " + E", hl.dsp.exec_cmd(fileManager), "Приложения: Файловый менеджер")
bind(mainMod .. " + S", hl.dsp.exec_cmd("zeditor"),   "Приложения: Zed")

-- Меню (rofi + скрипты из ~/.local/bin; путь через $HOME, чтобы не зависеть от PATH)
local home = os.getenv("HOME")
bind(mainMod .. " + R", hl.dsp.exec_cmd("rofi -show drun"),                     "Меню: Приложения")
bind(mainMod .. " + W", hl.dsp.exec_cmd(home .. "/.local/bin/wallpaper-pick"),  "Меню: Обои")
bind(mainMod .. " + A", hl.dsp.exec_cmd(home .. "/.local/bin/shortcuts"),       "Меню: Горячие клавиши")
bind(mainMod .. " + I", hl.dsp.exec_cmd("kitty -e btop"),                       "Меню: Монитор ресурсов")

-- Свободны: SUPER+T (смена темы — пока требует nixos-rebuild) и
-- SUPER+Z (на Arch это был обход блокировок, сервиса в NixOS нет).

-- Окна
bind(mainMod .. " + C", hl.dsp.window.close(),                        "Окна: Закрыть окно")
bind(mainMod .. " + V", hl.dsp.window.float({ action = "toggle" }),   "Окна: Плавающее / обычное")
bind(mainMod .. " + P", hl.dsp.window.pseudo(),                       "Окна: Pseudo-режим")
bind(mainMod .. " + J", hl.dsp.layout("togglesplit"),                 "Окна: Сменить направление разделения")
bind(mainMod .. " + M", hl.dsp.workspace.toggle_special("minimized"), "Окна: Свёрнутые окна")

-- Фокус стрелками
bind(mainMod .. " + left",  hl.dsp.focus({ direction = "left" }),  "Окна: Переключить фокус | Super + ← ↑ ↓ →")
bind(mainMod .. " + right", hl.dsp.focus({ direction = "right" }))
bind(mainMod .. " + up",    hl.dsp.focus({ direction = "up" }))
bind(mainMod .. " + down",  hl.dsp.focus({ direction = "down" }))

-- Рабочие столы 1-10
for i = 1, 10 do
    local key = i % 10 -- 10 -> клавиша 0
    bind(mainMod .. " + " .. key, hl.dsp.focus({ workspace = i }),
         i == 1 and "Рабочие столы: Перейти на стол | Super + 1…0" or nil)
    bind(mainMod .. " + SHIFT + " .. key, hl.dsp.window.move({ workspace = i }),
         i == 1 and "Рабочие столы: Перенести окно на стол | Super + Shift + 1…0" or nil)
end

bind(mainMod .. " + mouse_down", hl.dsp.focus({ workspace = "e+1" }), "Рабочие столы: Листать столы | Super + Колесо мыши")
bind(mainMod .. " + mouse_up",   hl.dsp.focus({ workspace = "e-1" }))
bind("ALT + Tab", hl.dsp.focus({ workspace = "previous" }), "Рабочие столы: Предыдущий стол")

-- Мышь
bind(mainMod .. " + mouse:272", hl.dsp.window.drag(),   "Окна: Перетащить окно",      { mouse = true })
bind(mainMod .. " + mouse:273", hl.dsp.window.resize(), "Окна: Изменить размер окна", { mouse = true })

-- Мультимедиа (wpctl из wireplumber, playerctl)
bind("XF86AudioRaiseVolume", hl.dsp.exec_cmd("wpctl set-volume -l 1 @DEFAULT_AUDIO_SINK@ 5%+"), "Система: Звук, плеер | Fn", { locked = true, repeating = true })
bind("XF86AudioLowerVolume", hl.dsp.exec_cmd("wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-"),      nil, { locked = true, repeating = true })
bind("XF86AudioMute",        hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"),     nil, { locked = true, repeating = true })
bind("XF86AudioMicMute",     hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle"),   nil, { locked = true, repeating = true })
bind("XF86AudioNext",  hl.dsp.exec_cmd("playerctl next"),       nil, { locked = true })
bind("XF86AudioPause", hl.dsp.exec_cmd("playerctl play-pause"), nil, { locked = true })
bind("XF86AudioPlay",  hl.dsp.exec_cmd("playerctl play-pause"), nil, { locked = true })
bind("XF86AudioPrev",  hl.dsp.exec_cmd("playerctl previous"),   nil, { locked = true })
