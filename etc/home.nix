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
    base16Scheme = {
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
      base0D = "7aa2f7"; # синий
      base0E = "bb9af7"; # фиолетовый
      base0F = "c0caf5";
    };

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
  programs.fish.enable = true;

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

  # ══ Hyprland и fastfetch: файлы ═════════════════════════════════════════════
  # Hyprland 0.55+ читает ~/.config/hypr/hyprland.lua и перечитывает его при
  # сохранении. keybinds.lua подключается через require(), colors.lua — dofile().
  xdg.configFile =
    {
      "hypr/hyprland.lua".source = ./configs/hypr/hyprland.lua;
      "hypr/keybinds.lua".source = ./configs/hypr/keybinds.lua;
      "hypr/colors.lua".source = ./configs/hypr/colors.lua;

      # fastfetch: jsonc с комментариями
      "fastfetch/config.jsonc".source = ./configs/fastfetch.jsonc;
    }
    # логотип — бинарник, его докачивает theme.sh; на этапе install его может
    # ещё не быть, поэтому линкуем только если файл реально существует
    // lib.optionalAttrs (builtins.pathExists ./configs/fastfetch/logo2.png) {
      "fastfetch/assets/logo2.png".source = ./configs/fastfetch/logo2.png;
    };
}
