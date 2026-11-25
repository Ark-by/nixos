# ─────────────────────────────────────────────────────────────────────────────
#  Пользовательский слой. Этап 1: Stylix + kitty + fish + starship + fastfetch.
#
#  Принцип: цвета и шрифты НЕ прописываем руками — их задаёт Stylix
#  (палитра + шрифты + прозрачность), а конфиги приложений содержат только
#  «геометрию» и поведение. Тогда смена темы = правка одного base16Scheme.
#
#  Дальше добавим: yazi, zed, waybar, hypridle/hyprpaper/hyprlock, wallpaper.
# ─────────────────────────────────────────────────────────────────────────────
{
  config,
  pkgs,
  lib,
  username,
  inputs,
  ...
}:
let
  # ══ ЕДИНСТВЕННЫЙ ИСТОЧНИК ЦВЕТОВ ═══════════════════════════════════════════
  # Tokyo Night в формате base16. Отсюда Stylix берёт палитру для kitty,
  # waybar, rofi, yazi, fish, starship, GTK, btop, а мы — цвета рамок Hyprland.
  # Меняешь здесь → перекрашивается всё после nixos-rebuild.
  palette = {
    base00 = "1a1b26"; # фон
    base01 = "16161e";
    base02 = "2f3549";
    base03 = "444b6a"; # комментарии
    base04 = "787c99";
    base05 = "a9b1d6"; # основной текст
    base06 = "cbccd1";
    base07 = "d5d6db";
    base08 = "f7768e"; # красный
    base09 = "ff9e64"; # оранжевый
    base0A = "e0af68"; # жёлтый
    base0B = "9ece6a"; # зелёный
    base0C = "7dcfff"; # циан
    base0D = "7aa2f7"; # синий (акцент)
    base0E = "bb9af7"; # фиолетовый
    base0F = "c0caf5";
  };
in
{
  imports = [ inputs.stylix.homeModules.default ];

  home = {
    inherit username;
    homeDirectory = "/home/${username}";
    stateVersion = "26.05";
  };

  programs.home-manager.enable = true;

  # ══ Stylix ══════════════════════════════════════════════════════════════════
  stylix = {
    enable = true;

    # Tokyo Night: та же палитра, что была в ark-tokyonight из репозитория.
    # Задаём инлайном, чтобы не зависеть от имён файлов в base16-schemes.
    polarity = "dark";
    base16Scheme = palette;

    fonts = {
      monospace = {
        name = "JetBrainsMono Nerd Font Mono";
        package = pkgs.nerd-fonts.jetbrains-mono;
      };
      sansSerif = {
        name = "Noto Sans";
        package = pkgs.noto-fonts;
      };
      serif = {
        name = "Noto Serif";
        package = pkgs.noto-fonts;
      };
      emoji = {
        name = "Noto Color Emoji";
        package = pkgs.noto-fonts-color-emoji;
      };
      sizes = {
        terminal = 10.5;
        applications = 10;
        desktop = 10;
        popups = 10;
      };
    };

    # Прозрачность терминала — как background_opacity 0.8 в старом kitty.conf
    opacity.terminal = 0.8;

    # У Stylix есть цель для Zed, но она БЕЗ mkDefault ставит
    # userSettings.theme = "Base16 …" и шрифты — это конфликтует с нашей темой
    # Ark Tokyo Night. Цель выключаем, тему подключаем файлом.
    targets.zed.enable = false;
  };

  # ══ kitty ═══════════════════════════════════════════════════════════════════
  # Цвета и шрифт подставляет Stylix; здесь только то, что было в kitty.conf.
  programs.kitty = {
    enable = true;
    settings = {
      window_padding_width = 10;
      # background_opacity не дублируем: его задаёт stylix.opacity.terminal
      dynamic_background_opacity = true;
    };
    keybindings = {
      "ctrl+c" = "copy_and_clear_or_interrupt";
      "ctrl+v" = "paste_from_clipboard";
    };
    shellIntegration.enableFishIntegration = true;
  };

  # ══ fish ════════════════════════════════════════════════════════════════════
  # Алиасы из старого .zshrc добавим отдельным шагом, когда сверим список.
  programs.fish = {
    enable = true;

    # fastfetch при открытии kitty. FASTFETCH_SHOWN не даёт ему срабатывать
    # повторно во вложенных fish. Хочешь во всех терминалах — убери проверку TERM.
    interactiveShellInit = ''
      if status is-interactive; and not set -q FASTFETCH_SHOWN; and test "$TERM" = xterm-kitty
          set -gx FASTFETCH_SHOWN 1
          fastfetch
      end
    '';
  };

  # ══ btop ════════════════════════════════════════════════════════════════════
  # Через home-manager, а не systemPackages, чтобы Stylix применил к нему тему
  # (цель btop включается только когда включён programs.btop).
  programs.btop.enable = true;

  # ══ starship ════════════════════════════════════════════════════════════════
  # Интеграцию с fish и цвета Stylix делают сами (targets.starship).
  # Тему ark перенесём сюда же, когда перепишем zsh-тему в starship.toml.
  programs.starship = {
    enable = true;
    settings = {
      add_newline = false;
      scan_timeout = 10;
      command_timeout = 1000;
    };
  };

  # ══ waybar ══════════════════════════════════════════════════════════════════
  # Палитру и шрифт подставляет Stylix (он пишет @define-color base00…base0F
  # и базовый CSS). Наш style дописывается через mkAfter — поэтому идёт
  # последним и может переопределять геометрию, используя те же переменные.
  programs.waybar = {
    enable = true;
    systemd.enable = true; # стартует с graphical-session.target, exec-once не нужен

    settings = [
      {
        layer = "top";
        position = "top";
        height = 34;
        spacing = 6;

        "margin-top" = 6;
        "margin-left" = 10;
        "margin-right" = 10;

        "modules-left" = [
          "hyprland/workspaces"
          "hyprland/window"
        ];
        "modules-center" = [ "clock" ];
        "modules-right" = [
          "tray"
          "pulseaudio"
          "network"
          "cpu"
          "memory"
          "hyprland/language"
        ];

        "hyprland/workspaces" = {
          format = "{name}";
          "on-click" = "activate";
          "all-outputs" = true;
          "persistent-workspaces" = {
            "*" = [
              1
              2
              3
              4
              5
              6
              7
              8
              9
              10
            ];
          };
        };

        "hyprland/window" = {
          format = "{title}";
          "max-length" = 70;
          "separate-outputs" = true;
        };

        "hyprland/language" = {
          format = "{short}";
          "format-en" = "EN";
          "format-ru" = "RU";
        };

        clock = {
          format = "{:%H:%M}";
          "tooltip-format" = "{:%A, %d %B %Y}";
        };

        pulseaudio = {
          format = "{icon} {volume}%";
          "format-muted" = " muted";
          "format-icons" = [
            "󰕿"
            "󰖀"
            "󰕾"
          ];
          "on-click" = "wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle";
          "on-scroll-up" = "wpctl set-volume -l 1 @DEFAULT_AUDIO_SINK@ 5%+";
          "on-scroll-down" = "wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-";
        };

        network = {
          "format-wifi" = "󰤨 {essid} {signalStrength}%";
          "format-ethernet" = "󰈀 {ipaddr}";
          "format-disconnected" = "󰤭";
          "tooltip-format" = "{ifname} → {gwaddr}";
        };

        cpu = {
          format = " {usage}%";
          interval = 3;
        };

        memory = {
          format = "󰍛 {used:0.1f}/{total:0.1f} GiB";
          interval = 5;
        };

        tray = {
          spacing = 8;
          "icon-size" = 16;
        };
      }
    ];

    style = lib.mkAfter ''
      * {
        border: none;
        border-radius: 0;
        min-height: 0;
        padding: 0;
        margin: 0;
      }

      window#waybar {
        background: alpha(@base00, 0.85);
        border-radius: 12px;
        color: @base05;
        padding: 0 10px;
      }

      .modules-left, .modules-center, .modules-right {
        padding: 0 4px;
      }

      #workspaces button {
        padding: 0 9px;
        margin: 4px 2px;
        border-radius: 8px;
        color: @base04;
        background: transparent;
      }

      #workspaces button:hover {
        background: alpha(@base02, 0.8);
        color: @base05;
      }

      #workspaces button.active {
        background: @base0D;
        color: @base00;
      }

      #workspaces button.urgent {
        background: @base08;
        color: @base00;
      }

      #window {
        color: @base04;
      }

      #clock {
        color: @base0D;
        font-weight: 600;
      }

      #cpu, #memory, #pulseaudio, #network, #language {
        padding: 0 8px;
        color: @base05;
      }

      #cpu:hover, #memory:hover, #pulseaudio:hover, #network:hover, #language:hover, #clock:hover {
        color: @base0C;
      }

      #tray {
        padding: 0 4px;
      }

      tooltip {
        background: @base00;
        border: 1px solid @base0D;
        border-radius: 8px;
      }

      tooltip label {
        color: @base05;
      }
    '';
  };

  # ══ yazi ════════════════════════════════════════════════════════════════════
  # Из Ark-by/arch (exp): показывать скрытые, Enter = войти в папку или открыть
  # файл (smart-enter), текст открывать в Zed.
  #
  # Отличия от оригинала:
  #   • opener использует "$@" вместо устаревшего %s;
  #   • desc "Sublime Text" заменён на "Zed";
  #   • добавлены [open] правила, иначе Enter на файле уходил бы в xdg-open.
  # Тему ark.yazi перенесём вместе с zed-темой (флейвор — отдельный шаг).
  programs.yazi = {
    enable = true;
    shellWrapperName = "y";

    # yazi определяет mime через `file`; без него text/* не сработает и
    # Enter на файле уйдёт в xdg-open вместо Zed.
    extraPackages = with pkgs; [ file ];

    settings = {
      mgr.show_hidden = true; # как в yazi.toml

      opener.edit = [
        {
          run = ''zeditor -w "$@"'';
          desc = "Zed";
          block = false;
        }
      ];

      # Порядок важен: срабатывает первое совпадение, * — последним.
      # Без правила * файл с неопознанным mime не открылся бы вообще.
      open.rules = [
        { mime = "text/*"; use = "edit"; }
        { mime = "application/json"; use = "edit"; }
        { mime = "application/toml"; use = "edit"; }
        { mime = "application/x-yaml"; use = "edit"; }
        { mime = "application/x-shellscript"; use = "edit"; }
        { mime = "application/x-*"; use = "edit"; }
        { mime = "inode/x-empty"; use = "edit"; }
        { mime = "*"; use = "open"; }
      ];
    };

    keymap.mgr.prepend_keymap = [
      {
        on = [ "<Enter>" ];
        run = "plugin smart-enter";
        desc = "Войти в папку или открыть файл";
      }
      {
        on = [ "~" ];
        run = "help";
        desc = "Справка по клавишам";
      }
      {
        on = [ "Ё" ];
        run = "help";
        desc = "Справка (рус. раскладка, Shift)";
      }
    ];

    plugins.smart-enter = ./configs/yazi/plugins/smart-enter.yazi;
  };

  # ══ Zed ═════════════════════════════════════════════════════════════════════
  # Настройки из config/zed/settings.json (exp). Тема — файл ark-tokyonight.json,
  # его скачивает theme.sh (как логотип), ниже он линкуется только если есть.
  programs.zed-editor = {
    enable = true;
    userSettings = {
      theme = "Ark Tokyo Night";
      buffer_font_family = "JetBrainsMono Nerd Font Mono";
      buffer_font_size = 14.0;
      ui_font_family = "JetBrainsMono Nerd Font";
      ui_font_size = 14.0;
      terminal = {
        font_family = "JetBrainsMono Nerd Font Mono";
        font_size = 14.0;
      };
    };
  };

  # ══ Hyprland и fastfetch: файлы ═════════════════════════════════════════════
  # Hyprland 0.55+ читает ~/.config/hypr/hyprland.lua и перечитывает его при
  # сохранении. keybinds.lua подключается через require(), colors.lua — dofile().
  # ══ Скрипты простоя ═════════════════════════════════════════════════════════
  # По простою уводим сессию на пустой стол __idle__, при активности — обратно.
  # Блокировки экрана нет специально.
  home.file = {
    ".local/bin/hypr-idle-hide" = {
      source = ./configs/bin/hypr-idle-hide;
      executable = true;
    };
    ".local/bin/hypr-idle-restore" = {
      source = ./configs/bin/hypr-idle-restore;
      executable = true;
    };
    ".local/bin/wallpaper-pick" = {
      source = ./configs/bin/wallpaper-pick;
      executable = true;
    };
    ".local/bin/shortcuts" = {
      source = ./configs/bin/shortcuts;
      executable = true;
    };
  };

  xdg.configFile =
    {
      # hypridle: 300 с простоя → hypr-idle-hide, возврат активности → restore.
      # Путь собираем из homeDirectory, чтобы не хардкодить /home/ark.
      "hypr/hypridle.conf".text = ''
        listener {
            timeout = 300

            on-timeout = ${config.home.homeDirectory}/.local/bin/hypr-idle-hide

            on-resume = ${config.home.homeDirectory}/.local/bin/hypr-idle-restore
        }
      '';

      "hypr/hyprland.lua".source = ./configs/hypr/hyprland.lua;

      # Рамки Hyprland — из той же палитры, что и всё остальное.
      # (отдельной цели Stylix для Hyprland нет, поэтому генерируем сами)
      "hypr/colors.lua".text = ''
        return {
          active   = "rgba(${palette.base0D}ff)",
          inactive = "rgba(${palette.base04}aa)",
        }
      '';

      # hyprpaper: обои берём из ~/Pictures/Wallpapers/current.png — это симлинк
      # на выбранную через SUPER+W картинку. IPC включён, чтобы скрипт менял
      # обои без рестарта демона.
      "hypr/hyprpaper.conf".text = ''
        ipc = on
        preload = ${config.home.homeDirectory}/Pictures/Wallpapers/current.png
        wallpaper = ,${config.home.homeDirectory}/Pictures/Wallpapers/current.png
      '';
      "hypr/keybinds.lua".source = ./configs/hypr/keybinds.lua;

      # fastfetch: jsonc с комментариями
      "fastfetch/config.jsonc".source = ./configs/fastfetch.jsonc;
    }
    # логотип — бинарник, его докачивает theme.sh; на этапе install его может
    # ещё не быть, поэтому линкуем только если файл реально существует
    // lib.optionalAttrs (builtins.pathExists ./configs/fastfetch/logo2.png) {
      "fastfetch/assets/logo2.png".source = ./configs/fastfetch/logo2.png;
    }
    // lib.optionalAttrs (builtins.pathExists ./configs/zed/themes/ark-tokyonight.json) {
      "zed/themes/ark-tokyonight.json".source = ./configs/zed/themes/ark-tokyonight.json;
    };
}
