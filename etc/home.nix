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
