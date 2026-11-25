#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
#  Установка стека: NixOS 26.05 + Hyprland + HyprLogin + Waybar + kitty +
#  fish + starship + fastfetch + yazi + Zed + Firefox + RustDesk + home-manager
#
#  Один файл: флейк и все модули зашиты внутрь, рядом ничего не нужно.
#    sudo bash install.sh            — обычная установка (HyprLogin)
#    sudo bash install.sh --safe     — экран входа tuigreet (если HyprLogin
#                                      не поднимется на NVIDIA/Wayland)
#    sudo bash install.sh --help     — короткая справка
#
#  Повторный запуск безопасен: бэкап делается заново, файлы перезаписываются.
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

C_OK=$'\033[1;32m'; C_ERR=$'\033[1;31m'; C_HDR=$'\033[1;36m'; C_DIM=$'\033[2m'; C_OFF=$'\033[0m'
say()  { printf '\n%s▶ %s%s\n' "$C_HDR" "$*" "$C_OFF"; }
ok()   { printf '%s  ✔ %s%s\n' "$C_OK" "$*" "$C_OFF"; }
warn() { printf '%s  ! %s%s\n' "$C_ERR" "$*" "$C_OFF"; }
die()  { printf '\n%s✘ %s%s\n' "$C_ERR" "$*" "$C_OFF" >&2; exit 1; }

SAFE=0
for arg in "$@"; do
  case "$arg" in
    --safe) SAFE=1 ;;
    -h | --help)
      sed -n '2,12p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *) die "Неизвестный аргумент: $arg (есть --safe, --help)" ;;
  esac
done

trap 'printf "\n%s✘ Скрипт остановился на строке %s.%s\n" "$C_ERR" "$LINENO" "$C_OFF"' ERR

# ── проверки окружения ──────────────────────────────────────────────────────
[ "$(id -u)" -eq 0 ] || die "Нужен root: sudo bash install.sh"
command -v nixos-version >/dev/null 2>&1 || die "Это не NixOS (нет nixos-version)"
[ -f /etc/nixos/hardware-configuration.nix ] \
  || die "Нет /etc/nixos/hardware-configuration.nix — система ставилась не штатным установщиком?"
[ "$(uname -m)" = "x86_64" ] || die "Ожидается x86_64, а тут $(uname -m)"

say "Система"
printf '  %s\n' "$(nixos-version)"
printf '  ядро: %s\n' "$(uname -r)"

avail_kb="$(df -Pk /nix 2>/dev/null | awk 'NR==2 {print $4}')"
if [ -n "${avail_kb:-}" ] && [ "$avail_kb" -lt $((15 * 1024 * 1024)) ]; then
  die "Мало места на /nix: $((avail_kb / 1024 / 1024)) ГБ, нужно минимум 15 ГБ (zed + rustdesk тяжёлые)"
fi
ok "места на /nix хватает"

if command -v curl >/dev/null 2>&1; then
  curl -fsI --max-time 10 https://cache.nixos.org/nix-cache-info >/dev/null 2>&1 \
    || die "Нет доступа к cache.nixos.org — подключи сеть (nmtui) и повтори"
  ok "интернет есть"
else
  getent hosts cache.nixos.org >/dev/null 2>&1 \
    || die "DNS не резолвит cache.nixos.org — проверь сеть (nmtui)"
  ok "DNS отвечает (curl нет, но это не критично)"
fi

if [ "$(tty 2>/dev/null || true)" = "/dev/tty1" ]; then
  warn "Ты в tty1 — при активации её займёт greetd и тебя перекинет на экран входа."
  warn "Лучше: Ctrl+Alt+F2, войти в tty2 и запустить скрипт там."
  read -r -p "    Продолжить всё равно? [y/N] " ans || true
  [ "${ans:-n}" = "y" ] || exit 1
fi

# ── бэкап ───────────────────────────────────────────────────────────────────
say "Бэкап /etc/nixos"
BK="/var/backups/nixos-$(date +%F_%H%M%S)"
mkdir -p "$BK"
cp -a /etc/nixos/. "$BK/"
ok "$BK"

# ── пользователь ────────────────────────────────────────────────────────────
say "Пользователь"
USER_NAME="${SUDO_USER:-}"
if [ -z "$USER_NAME" ] || [ "$USER_NAME" = "root" ]; then
  USER_NAME="$(awk -F: '$3 >= 1000 && $3 < 65534 && $7 !~ /(nologin|false)$/ {print $1; exit}' /etc/passwd)"
fi
[ -n "$USER_NAME" ] || die "Не нашёл обычного пользователя. Запусти: sudo SUDO_USER=имя bash install.sh"
id "$USER_NAME" >/dev/null 2>&1 || die "Пользователя $USER_NAME нет в системе"
ok "$USER_NAME (домашняя: $(getent passwd "$USER_NAME" | cut -d: -f6))"

# ── старый конфиг → system.nix ──────────────────────────────────────────────
say "Прежний configuration.nix → system.nix"
if [ -f /etc/nixos/configuration.nix ] && [ ! -f /etc/nixos/system.nix ]; then
  mv /etc/nixos/configuration.nix /etc/nixos/system.nix
  ok "переименован (пользователь, пароль, хостнейм сохранены)"
elif [ -f /etc/nixos/system.nix ]; then
  ok "system.nix уже на месте — не трогаю"
else
  die "Нет ни configuration.nix, ни system.nix"
fi

# ── flake.nix ───────────────────────────────────────────────────────────────
say "Раскладываю flake.nix"
cat > /etc/nixos/flake.nix <<'NIXFLAKE'
# ─────────────────────────────────────────────────────────────────────────────
#  NixOS 26.05 (Yarara) + Hyprland — Ark-by
#
#  Схема:
#    system.nix      ← прежний configuration.nix (хостнейм, юзер, пароль)
#    hypr-stack.nix  ← системный слой: Hyprland, HyprLogin, NVIDIA, пакеты
#    home.nix        ← пользовательский слой: Stylix + kitty + fish + starship
#    configs/        ← файлы, которые нельзя разложить по опциям (fastfetch и т.п.)
#
#  Имя пользователя подставляет скрипт (sed) вместо @USERNAME@.
# ─────────────────────────────────────────────────────────────────────────────
{
  description = "NixOS 26.05 + Hyprland (Ark-by)";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";

    home-manager = {
      url = "github:nix-community/home-manager/release-26.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # HyprLogin в nixpkgs нет (AUR-only проект), поэтому берём из его же флейка.
    hyprlogin = {
      url = "github:AuthenticSm1les/hyprlogin";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Stylix: палитра + шрифты + обои для всех приложений сразу.
    stylix = {
      url = "github:nix-community/stylix/release-26.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    inputs@{
      self,
      nixpkgs,
      home-manager,
      ...
    }:
    let
      system = "x86_64-linux";
      username = "@USERNAME@";

      cfg = nixpkgs.lib.nixosSystem {
        inherit system;
        specialArgs = { inherit inputs username; };
        modules = [
          ./system.nix
          ./hypr-stack.nix

          # Без этого нет опций programs.hyprlogin.
          inputs.hyprlogin.nixosModules.default

          home-manager.nixosModules.home-manager
          {
            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;
            home-manager.backupFileExtension = "hm-bak";
            home-manager.extraSpecialArgs = { inherit inputs username; };
            home-manager.users.${username} = import ./home.nix;
          }
        ];
      };
    in
    {
      nixosConfigurations.nixos = cfg;
      nixosConfigurations.desktop = cfg;
    };
}
NIXFLAKE
sed -i "s/@USERNAME@/${USER_NAME}/g" /etc/nixos/flake.nix
if grep -q "@USERNAME@" /etc/nixos/flake.nix; then
  die "Не удалось подставить имя пользователя в flake.nix"
fi
ok "flake.nix"

# ── hypr-stack.nix ──────────────────────────────────────────────────────────
say "Раскладываю hypr-stack.nix"
cat > /etc/nixos/hypr-stack.nix <<'NIXSTACK'
# ─────────────────────────────────────────────────────────────────────────────
#  Системный слой стека. Здесь только то, что требует root:
#  драйвер GPU, композитор, экран входа, пакеты, шрифты, звук, порталы.
#
#  Пользовательские конфиги (hyprland.lua, waybar, kitty, fish, starship,
#  yazi, zed, fastfetch) сюда НЕ кладём — они приедут из Ark-by/arch
#  на этапе настройки, в home.nix.
# ─────────────────────────────────────────────────────────────────────────────
{
  config,
  pkgs,
  lib,
  inputs,
  username,
  ...
}:
let
  # ── переключатель экрана входа ─────────────────────────────────────────────
  #  true  → HyprLogin (graphical greeter на базе hyprlock, как на Arch)
  #  false → tuigreet (простой TUI-логин — запасной вариант, если HyprLogin
  #          не поднимается на этой связке NVIDIA/Wayland)
  #
  #  Переключить:  sudo sed -i 's/useHyprlogin = true/useHyprlogin = false/' \
  #                  /etc/nixos/hypr-stack.nix
  #                sudo nixos-rebuild switch --flake /etc/nixos#nixos
  useHyprlogin = true;
in
{
  # ══ flakes ══════════════════════════════════════════════════════════════════
  # Без этого nixos-rebuild --flake не работает (в свежей системе выключено).
  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];

  # rustdesk, nvidia-драйвер — несвободные пакеты.
  # ВАЖНО: nixpkgs.config нельзя оборачивать в lib.mkDefault — это не обычная
  # опция, внутри неё mkDefault превращается в мусорный объект вместо bool.
  # Две обычные записи allowUnfree корректно сливаются, так что конфликта нет.
  nixpkgs.config.allowUnfree = true;

  # HyprLogin собирается из исходников против библиотек 26.05
  # (hyprlang/hyprutils/hyprgraphics уже лежат в кэше nixos.org — сборка быстрая).
  nixpkgs.overlays = [ inputs.hyprlogin.overlays.default ];

  # ══ Hyprland ════════════════════════════════════════════════════════════════
  programs.hyprland = {
    enable = true;
    withUWSM = true; # сессия через uwsm — правильный systemd-старт юнитов
    xwayland.enable = true; # нужен RustDesk и старым X11-приложениям
  };

  # ══ Экран входа A: greetd + HyprLogin ═══════════════════════════════════════
  # Модуль сам:
  #   • включает greetd и прописывает default_session = start-hyprland + greeter lua
  #   • пишет /etc/hyprlogin/hyprlogin.conf (тема hyprlock-совместимая)
  #   • создаёт /var/cache/hyprlogin для «запомнить пользователя/сессию»
  #   • кладёт список сессий из /run/current-system/sw/share/wayland-sessions
  programs.hyprlogin = lib.mkIf useHyprlogin {
    enable = true;
    package = pkgs.hyprlogin;
    extraConfig = ''
      sessions:remember_user = true
      sessions:remember_session = true
    '';
  };

  # ══ Экран входа B: greetd + tuigreet (запасной) ═════════════════════════════
  services.greetd = lib.mkIf (!useHyprlogin) {
    enable = true;
    useTextGreeter = true;
    settings.default_session = {
      command = "${pkgs.tuigreet}/bin/tuigreet --time --remember --sessions /run/current-system/sw/share/wayland-sessions";
      user = "greeter";
    };
  };

  # Greeter — системный пользователь без групп. Без video/render Hyprland
  # не сможет открыть /dev/dri и экран входа останется чёрным.
  users.groups.video = { };
  users.groups.render = { };
  users.users.greeter.extraGroups = [
    "video"
    "render"
  ];

  # ══ NVIDIA RTX 3050 (Ampere) ════════════════════════════════════════════════
  services.xserver.videoDrivers = [ "nvidia" ];

  hardware.nvidia = {
    modesetting.enable = true; # обязательное условие для Wayland/Hyprland
    open = true; # для Turing+ сам модуль NixOS требует задать open явно
    nvidiaSettings = true;
    package = config.boot.kernelPackages.nvidiaPackages.stable;
  };

  boot.kernelParams = [
    "nvidia_drm.modeset=1"
    "nvidia_drm.fbdev=1"
  ];

  # Модуль nvidia грузит nvidia* в boot.kernelModules ТОЛЬКО при включённом
  # services.xserver, а у нас чистый Wayland. Грузим сами, иначе до greeter
  # драйвер может не подняться.
  boot.kernelModules = [
    "nvidia"
    "nvidia_modeset"
    "nvidia_drm"
  ];

  hardware.graphics.enable = lib.mkDefault true;
  hardware.cpu.amd.updateMicrocode = true;
  hardware.enableRedistributableFirmware = true;

  # Переменные для NVIDIA + Wayland. Действуют и в сессии, и у greeter
  # (greetd запускает PAM-сессию, /etc/environment подхватывается).
  environment.sessionVariables = {
    NIXOS_OZONE_WL = "1";
    LIBVA_DRIVER_NAME = "nvidia";
    GBM_BACKEND = "nvidia-drm";
    __GLX_VENDOR_LIBRARY_NAME = "nvidia";
  };

  # ══ Звук (Firefox, RustDesk) ════════════════════════════════════════════════
  services.pipewire = {
    enable = lib.mkDefault true;
    alsa.enable = lib.mkDefault true;
    pulse.enable = lib.mkDefault true;
  };

  # ══ Порталы: файловые диалоги, скриншоты, screen-share для RustDesk ═════════
  # portal-hyprland добавляет сам модуль Hyprland, gtk — для Firefox/GTK-приложений.
  xdg.portal.extraPortals = [ pkgs.xdg-desktop-portal-gtk ];

  # ══ Оболочка по умолчанию ═══════════════════════════════════════════════════
  # users.defaultUserShell НЕ трогаем: он уже определён (модуль shell'а или
  # system.nix), а два mkDefault NixOS не сливает — «conflicting definition
  # values». Нам достаточно явно зафиксировать шелл своему пользователю.
  # mkForce — чтобы не зависеть от того, что прописано в system.nix.
  programs.fish.enable = true;
  users.users.${username}.shell = lib.mkForce pkgs.fish;

  # ══ Подкачка в RAM ══════════════════════════════════════════════════════════
  zramSwap.enable = lib.mkDefault true;

  # ══ Шрифты ══════════════════════════════════════════════════════════════════
  fonts.packages = with pkgs; [
    noto-fonts
    noto-fonts-color-emoji # в 26.05 переименован из noto-fonts-emoji
    nerd-fonts.jetbrains-mono # иконки для waybar/kitty/starship
  ];

  # ══ SSH (пригодится, если понадобится помощь удалённо) ══════════════════════
  services.openssh.enable = lib.mkDefault true;

  # ══ Пакеты стека ════════════════════════════════════════════════════════════
  environment.systemPackages = with pkgs; [
    # терминал и оболочка
    kitty
    fish
    starship
    fastfetch
    yazi

    # приложения
    firefox
    zed-editor
    rustdesk

    # Hypr-экосистема
    hypridle
    hyprpaper
    hyprlock
    waybar
    hyprpolkitagent

    # мелочи, без которых Wayland-десктоп неудобен
    wl-clipboard
    cliphist
    grim
    slurp
    libnotify
    xdg-utils

    # для биндов: громкость (wpctl) и медиа-клавиши (playerctl)
    wireplumber
    playerctl
  ];
}
NIXSTACK
if [ "$SAFE" = "1" ]; then
  sed -i 's/useHyprlogin = true;/useHyprlogin = false;/' /etc/nixos/hypr-stack.nix
  ok "hypr-stack.nix (--safe: экран входа tuigreet)"
else
  ok "hypr-stack.nix"
fi

# ── home.nix ────────────────────────────────────────────────────────────────
say "Раскладываю home.nix"
cat > /etc/nixos/home.nix <<'NIXHOME'
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
NIXHOME
ok "home.nix"

# ── конфиги приложений (home.nix на них ссылается) ──────────────────────────
say "Раскладываю конфиги приложений"
install -d -m 0755 /etc/nixos/configs/hypr /etc/nixos/configs/fastfetch

cat > /etc/nixos/configs/hypr/hyprland.lua <<'HYPRLAND'
-- ═══════════════════════════════════════════════════════════════════════════
--  Hyprland 0.55+ (Lua). Портировано из Ark-by/arch (ветка exp).
--  Отличия от Arch-версии:
--    • автозапуск: hyprpaper + hypridle + hyprpolkitagent вместо quickshell/dunst
--      (waybar добавим, когда будет его конфиг)
--    • цвета берутся из colors.lua — рядом, его пишем мы (Stylix-палитра)
--  Hyprland перечитывает этот файл при сохранении; вручную — hyprctl reload
-- ═══════════════════════════════════════════════════════════════════════════

------------------
---- MONITORS ----
------------------

hl.monitor({
    output   = "HDMI-A-1",
    mode     = "1920x1080@165",
    position = "auto",
    scale    = "auto",
})


---------------------
---- MY PROGRAMS ----
---------------------

local terminal    = "kitty"
local fileManager = "kitty -e yazi"
local browser     = "firefox"


-------------------
---- AUTOSTART ----
-------------------

-- Демоны рабочего стола. waybar сюда добавим после его конфига.
hl.on("hyprland.start", function()
    hl.exec_cmd("hyprpaper")
    hl.exec_cmd("hypridle")
    hl.exec_cmd("hyprpolkitagent")
end)


-------------------------------
---- ENVIRONMENT VARIABLES ----
-------------------------------

hl.env("XCURSOR_SIZE", "24")
hl.env("HYPRCURSOR_SIZE", "24")


-----------------------
---- LOOK AND FEEL ----
-----------------------

-- Палитра темы (файл лежит рядом: ~/.config/hypr/colors.lua)
local colors = dofile(os.getenv("HOME") .. "/.config/hypr/colors.lua")

hl.config({
    general = {
        gaps_in  = 5,
        gaps_out = 20,

        border_size = 2,

        col = {
            active_border   = colors.active,
            inactive_border = colors.inactive,
        },

        resize_on_border = false,
        allow_tearing    = false,
        layout           = "dwindle",
    },

    decoration = {
        rounding       = 10,
        rounding_power = 2,

        active_opacity   = 1,
        inactive_opacity = 1,

        shadow = {
            enabled      = true,
            range        = 4,
            render_power = 3,
            color        = 0xee1a1a1a,
        },

        blur = {
            enabled  = true,
            size     = 3,
            passes   = 1,
            vibrancy = 0.1696,
        },
    },

    animations = {
        enabled = true,
    },
})

-- Кривые и анимации по умолчанию
hl.curve("easeOutQuint",   { type = "bezier", points = { {0.23, 1},    {0.32, 1}    } })
hl.curve("easeInOutCubic", { type = "bezier", points = { {0.65, 0.05}, {0.36, 1}    } })
hl.curve("linear",         { type = "bezier", points = { {0, 0},       {1, 1}       } })
hl.curve("almostLinear",   { type = "bezier", points = { {0.5, 0.5},   {0.75, 1}    } })
hl.curve("quick",          { type = "bezier", points = { {0.15, 0},    {0.1, 1}     } })
hl.curve("easy",           { type = "spring", mass = 1, stiffness = 238.1191, dampening = 24.21279333 })

hl.animation({ leaf = "global",        enabled = true,  speed = 10,   bezier = "default" })
hl.animation({ leaf = "border",        enabled = true,  speed = 5.39, bezier = "easeOutQuint" })
hl.animation({ leaf = "windows",       enabled = true,  speed = 4.79, spring = "easy" })
hl.animation({ leaf = "windowsIn",     enabled = true,  speed = 4.1,  spring = "easy",         style = "popin 87%" })
hl.animation({ leaf = "windowsOut",    enabled = true,  speed = 1.49, bezier = "linear",       style = "popin 87%" })
hl.animation({ leaf = "fadeIn",        enabled = true,  speed = 1.73, bezier = "almostLinear" })
hl.animation({ leaf = "fadeOut",       enabled = true,  speed = 1.46, bezier = "almostLinear" })
hl.animation({ leaf = "fade",          enabled = true,  speed = 3.03, bezier = "quick" })
hl.animation({ leaf = "layers",        enabled = true,  speed = 3.81, bezier = "easeOutQuint" })
hl.animation({ leaf = "layersIn",      enabled = true,  speed = 4,    bezier = "easeOutQuint", style = "fade" })
hl.animation({ leaf = "layersOut",     enabled = true,  speed = 1.5,  bezier = "linear",       style = "fade" })
hl.animation({ leaf = "fadeLayersIn",  enabled = true,  speed = 1.79, bezier = "almostLinear" })
hl.animation({ leaf = "fadeLayersOut", enabled = true,  speed = 1.39, bezier = "almostLinear" })
hl.animation({ leaf = "workspaces",    enabled = true,  speed = 1.94, bezier = "almostLinear", style = "fade" })
hl.animation({ leaf = "workspacesIn",  enabled = true,  speed = 1.21, bezier = "almostLinear", style = "fade" })
hl.animation({ leaf = "workspacesOut", enabled = true,  speed = 1.94, bezier = "almostLinear", style = "fade" })
hl.animation({ leaf = "zoomFactor",    enabled = true,  speed = 7,    bezier = "quick" })

hl.config({
    dwindle = {
        preserve_split = true,
    },
})

hl.config({
    master = {
        new_status = "master",
    },
})

hl.config({
    scrolling = {
        fullscreen_on_one_column = true,
    },
})


----------------
----  MISC  ----
----------------

hl.config({
    misc = {
        force_default_wallpaper = -1,
        disable_hyprland_logo   = false,
    },
})


---------------
---- INPUT ----
---------------

hl.config({
    input = {
        kb_layout  = "us,ru",
        kb_variant = "",
        kb_model   = "",
        kb_options = "grp:alt_shift_toggle",
        kb_rules   = "",

        follow_mouse = 1,
        sensitivity  = 0,

        touchpad = {
            natural_scroll = false,
        },
    },
})

hl.config({ cursor = { no_hardware_cursors = 1 }})

hl.gesture({
    fingers   = 3,
    direction = "horizontal",
    action    = "workspace"
})


---------------------
---- KEYBINDINGS ----
---------------------

require("keybinds")


--------------------------------
---- WINDOWS AND WORKSPACES ----
--------------------------------

hl.window_rule({
    name  = "suppress-maximize-events",
    match = { class = ".*" },

    suppress_event = "maximize",
})

hl.window_rule({
    -- Лечит перетаскивание в XWayland-окнах
    name  = "fix-xwayland-drags",
    match = {
        class      = "^$",
        title      = "^$",
        xwayland   = true,
        float      = true,
        fullscreen = false,
        pin        = false,
    },

    no_focus = true,
})

hl.window_rule({
    name  = "move-hyprland-run",
    match = { class = "hyprland-run" },

    move  = "20 monitor_h-120",
    float = true,
})
HYPRLAND

cat > /etc/nixos/configs/hypr/keybinds.lua <<'KEYBINDS'
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

-- Меню панели: на Arch это были вызовы quickshell (`qs ipc call ui ...`).
-- Вернём, когда настроим waybar со своими скриптами:
--   SUPER+R — лаунчер, SUPER+W — обои, SUPER+T — тема,
--   SUPER+Z — сервисы, SUPER+I — монитор, SUPER+A — справка.

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
KEYBINDS

cat > /etc/nixos/configs/hypr/colors.lua <<'COLORS'
-- Палитра для рамок окон. Значения — из Tokyo Night (Stylix base16).
-- Файл читает hyprland.lua через dofile(); меняется вместе с базовой палитрой.
return {
  active   = "rgba(7aa2f7ff)", -- base0D
  inactive = "rgba(565f89aa)",
}
COLORS

cat > /etc/nixos/configs/fastfetch.jsonc <<'FASTFETCH'
{
  "$schema": "https://github.com/fastfetch-cli/fastfetch/raw/dev/doc/json_schema.json",
  "logo": {
    "type": "kitty-direct",
    "source": "~/.config/fastfetch/assets/logo2.png",
    "width": 40
  },
  "display": {
    "color": "cyan"
  },

  "modules": [
    {
      "type": "custom",
      "format": "╭────────────────────────────────────────────────────────╮"
    },
    {
      "type": "title",
      "key": "    User",
      "keyColor": "blue",
      "format": "{1}@{2}",
      "outputColor": "white"
    },
    {
      "type": "os",
      "key": "   󰣇 OS",
      "keyColor": "blue",
      "format": "{2}",
      "outputColor": "white"
    },
    {
      "type": "kernel",
      "key": "    Kernel",
      "keyColor": "blue",
      "format": "{2}",
      "outputColor": "white"
    },
    {
      "type": "packages",
      "key": "   󰏗 Packages",
      "keyColor": "green",
      "outputColor": "white"
    },
    {
      "type": "cpu",
      "key": "    CPU",
      "keyColor": "cyan",
      "format": "{1} ({3}) @ {7}",
      "outputColor": "white"
    },
    {
      "type": "gpu",
      "key": "   󰊴 GPU",
      "keyColor": "cyan",
      "format": "{1} {2}",
      "outputColor": "white"
    },
    {
      "type": "memory",
      "key": "   󰍛 RAM",
      "keyColor": "cyan",
      "format": "{1} / {2} ({3})",
      "outputColor": "white"
    },
    {
      "type": "custom",
      "format": "╰────────────────────────────────────────────────────────╯"
    },

    {
      "type": "custom",
      "format": "╭────────────────────────────────────────────────────────╮"
    },

    {
      "type": "display",
      "key": "   󰍹 Display",
      "keyColor": "yellow",
      "format": "{1}x{2} @ {3}Hz ({7})",
      "outputColor": "white"
    },
    {
      "type": "wm",
      "key": "   󱗃 WM",
      "keyColor": "yellow",
      "format": "{2}",
      "outputColor": "white"
    },
    {
      "type": "terminal",
      "key": "    Terminal",
      "keyColor": "yellow",
      "format": "{2}",
      "outputColor": "white"
    },
    {
      "type": "uptime",
      "key": "   󰅐 Uptime",
      "keyColor": "magenta",
      "outputColor": "white"
    },
    {
      "type": "disk",
      "key": "   OS Age",
      "keyColor": "magenta",
      "format": "{days} days",
      "folders": "/",
      "outputColor": "white"
    },
    {
      "type": "disk",
      "key": "   󱦟 Disk",
      "keyColor": "magenta",
      "format": "{1} / {2} ({3})",
      "folders": "/",
      "outputColor": "white"
    },
    {
      "type": "custom",
      "format": "╰────────────────────────────────────────────────────────╯"
    },
    {
      "type": "colors",
      "symbol": "circle",
      "paddingLeft": 2
    },
    "break"
  ]
}
FASTFETCH

install -d -m 0755 /etc/nixos/configs/yazi/plugins/smart-enter.yazi
cat > /etc/nixos/configs/yazi/plugins/smart-enter.yazi/main.lua <<'YAZIPLUGIN'
--- @since 25.5.31
--- @sync entry

local function setup(self, opts) self.open_multi = opts.open_multi end

local function entry(self)
	local h = cx.active.current.hovered
	ya.emit(h and h.cha.is_dir and "enter" or "open", { hovered = not self.open_multi })
end

return { entry = entry, setup = setup }
YAZIPLUGIN
ok "configs/hypr/*.lua, configs/fastfetch.jsonc, configs/yazi/plugins/smart-enter.yazi (логотип докачает theme.sh)"

# ── flakes для этого запуска ────────────────────────────────────────────────
enable_flakes() {
  say "Включаю flakes"
  { grep -qs '^experimental-features' /etc/nix/nix.conf \
    || printf 'experimental-features = nix-command flakes\n' >> /etc/nix/nix.conf; } 2>/dev/null || true
  export NIX_CONFIG="experimental-features = nix-command flakes"
  ok "NIX_CONFIG выставлен"
}
enable_flakes

# ── сборка ──────────────────────────────────────────────────────────────────
say "nixos-rebuild switch"
printf '%s  Первый запуск качает nixpkgs + home-manager + hyprlogin и собирает.\n' "$C_DIM"
printf '  Обычно 10–40 минут, ~2–3 ГБ.%s\n' "$C_OFF"
nixos-rebuild switch --flake /etc/nixos#nixos --show-trace

# ── итог ────────────────────────────────────────────────────────────────────
say "Готово"
ok "поколение: $(nixos-version)"
ok "конфиги: /etc/nixos/{flake,hypr-stack,home,system}.nix"
ok "бэкап:   $BK"

cat <<'EOT'

  Дальше:
    1) sudo reboot
    2) появится экран входа → входишь в Hyprland
    3) проверки:  bash verify.sh  (лежит рядом с этим скриптом)

  Если вместо экрана входа чёрный экран:
    Ctrl+Alt+F2 → войти → одной строкой:
      sudo sed -i 's/useHyprlogin = true/useHyprlogin = false/' /etc/nixos/hypr-stack.nix
      sudo nixos-rebuild switch --flake /etc/nixos#nixos
    Это переключит вход на tuigreet, драйвер и пакеты не тронет.

  Откат:
    sudo nixos-rebuild switch --rollback
    меню systemd-boot → предыдущее поколение
    старые конфиги: /var/backups/nixos-*
EOT
