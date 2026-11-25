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
#    system.nix      ← твой прежний configuration.nix (хостнейм, юзер, пароль)
#    hypr-stack.nix  ← весь стек: Hyprland, HyprLogin, NVIDIA, пакеты
#    home.nix        ← home-manager: пока пусто, конфиги приедут из Ark-by/arch
#
#  Имя пользователя подставляет sed (см. шаг с flake.nix).
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
    # Оверлей hyprlogin собирает пакет из исходников против библиотек 26.05.
    hyprlogin = {
      url = "github:AuthenticSm1les/hyprlogin";
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

          # Без этой строки нет опций programs.hyprlogin: модуль живёт в самом
          # флейке hyprlogin, а не в nixpkgs (оверлей даёт только пакет).
          inputs.hyprlogin.nixosModules.default

          home-manager.nixosModules.home-manager
          {
            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;
            home-manager.backupFileExtension = "hm-bak";
            home-manager.extraSpecialArgs = { inherit username; };
            home-manager.users.${username} = import ./home.nix;
          }
        ];
      };
    in
    {
      # Два имени — чтобы `nixos-rebuild --flake /etc/nixos#nixos`
      # и старый `#desktop` работали одинаково.
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
#  Пользовательский слой (home-manager).
#
#  Здесь ПОКА ПУСТО специально: по плану fish/starship/kitty/waybar/yazi/zed/
#  fastfetch переносим из репозитория Ark-by/arch на этапе настройки.
#  Когда будем переносить — конфиги лягут сюда декларативно, а не копированием
#  в ~/.config, и тогда `nixos-rebuild switch` будет обновлять всё сразу.
# ─────────────────────────────────────────────────────────────────────────────
{ config, pkgs, lib, username, ... }:
{
  home = {
    inherit username;
    homeDirectory = "/home/${username}";
    stateVersion = "26.05";
  };

  programs.home-manager.enable = true;

  # Заглушка, чтобы файл был валидным модулем.
  home.packages = [ ];
}
NIXHOME
ok "home.nix"

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
