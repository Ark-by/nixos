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
  programs.fish.enable = true;
  users.defaultUserShell = lib.mkDefault pkgs.fish;
  users.users.${username}.shell = lib.mkDefault pkgs.fish;

  # ══ Подкачка в RAM ══════════════════════════════════════════════════════════
  zramSwap.enable = lib.mkDefault true;

  # ══ Шрифты ══════════════════════════════════════════════════════════════════
  fonts.packages = with pkgs; [
    noto-fonts
    noto-fonts-emoji
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
