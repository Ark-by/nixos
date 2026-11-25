#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
#  Настройка, этап 2: Hyprland (твои бинды) + fastfetch с твоим логотипом.
#  Этап 1 (Stylix/kitty/fish/starship) уже внутри — скрипт кладёт всё сразу,
#  поэтому его можно запускать повторно без вреда.
#
#  Запуск (из папки с этим файлом):  sudo bash theme.sh
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
SRC="$HERE/etc"
LOGO_URL="https://raw.githubusercontent.com/Ark-by/arch/exp/config/fastfetch/assets/logo2.png"

C_OK=$'\033[1;32m'; C_ERR=$'\033[1;31m'; C_HDR=$'\033[1;36m'; C_OFF=$'\033[0m'
say() { printf '\n%s▶ %s%s\n' "$C_HDR" "$*" "$C_OFF"; }
ok()  { printf '%s  ✔ %s%s\n' "$C_OK" "$*" "$C_OFF"; }
die() { printf '\n%s✘ %s%s\n' "$C_ERR" "$*" "$C_OFF" >&2; exit 1; }

trap 'printf "\n%s✘ Остановился на строке %s.%s\n" "$C_ERR" "$LINENO" "$C_OFF"' ERR

[ "$(id -u)" -eq 0 ] || die "Нужен root: sudo bash theme.sh"
command -v nixos-version >/dev/null 2>&1 || die "Это не NixOS"
[ -d "$SRC" ] || die "Рядом нет папки etc/ — скопируй всю папку, а не один скрипт"
[ -f /etc/nixos/system.nix ] || die "Нет /etc/nixos/system.nix — сначала заверши установку"

U="${SUDO_USER:-}"
if [ -z "$U" ] || [ "$U" = "root" ]; then
  U="$(awk -F: '$3 >= 1000 && $3 < 65534 && $7 !~ /(nologin|false)$/ {print $1; exit}' /etc/passwd)"
fi
[ -n "$U" ] || die "Не нашёл пользователя"
id "$U" >/dev/null 2>&1 || die "Пользователя $U нет"
ok "пользователь: $U"

say "Бэкап /etc/nixos"
BK="/var/backups/nixos-theme-$(date +%F_%H%M%S)"
mkdir -p "$BK"
cp -a /etc/nixos/. "$BK/"
ok "$BK"

say "Раскладываю конфиги"
install -d -m 0755 /etc/nixos/configs/hypr /etc/nixos/configs/fastfetch
install -m 0644 "$SRC/flake.nix"                       /etc/nixos/flake.nix
install -m 0644 "$SRC/home.nix"                        /etc/nixos/home.nix
install -m 0644 "$SRC/configs/fastfetch.jsonc"         /etc/nixos/configs/fastfetch.jsonc
install -m 0644 "$SRC/configs/hypr/hyprland.lua"       /etc/nixos/configs/hypr/hyprland.lua
install -m 0644 "$SRC/configs/hypr/keybinds.lua"       /etc/nixos/configs/hypr/keybinds.lua
install -m 0644 "$SRC/configs/hypr/colors.lua"         /etc/nixos/configs/hypr/colors.lua
sed -i "s/@USERNAME@/${U}/g" /etc/nixos/flake.nix
grep -q "@USERNAME@" /etc/nixos/flake.nix && die "не подставилось имя пользователя"
ok "flake.nix, home.nix, configs/hypr/*, configs/fastfetch.jsonc"

say "Логотип fastfetch"
if [ -s /etc/nixos/configs/fastfetch/logo2.png ]; then
  ok "logo2.png уже на месте ($(stat -c%s /etc/nixos/configs/fastfetch/logo2.png) байт)"
else
  command -v curl >/dev/null 2>&1 || die "нет curl — скачай logo2.png вручную в /etc/nixos/configs/fastfetch/"
  curl -fsSL --max-time 60 "$LOGO_URL" -o /etc/nixos/configs/fastfetch/logo2.png \
    || die "не скачался logo2.png; положи файл вручную: /etc/nixos/configs/fastfetch/logo2.png"
  ok "logo2.png скачан ($(stat -c%s /etc/nixos/configs/fastfetch/logo2.png) байт)"
fi

say "Сборка"
export NIX_CONFIG="experimental-features = nix-command flakes"
nixos-rebuild switch --flake /etc/nixos#nixos --show-trace

say "Готово"
ok "поколение: $(nixos-version)"
ok "бэкап: $BK"

cat <<'EOT'

  Проверки (без перезагрузки):
    hyprctl reload                  # перечитать конфиг (или сохрани файл — 0.55 сам)
    hyprctl getoption general:gaps_in   # должно быть 5
    kitty                           # цвета/шрифт/прозрачность
    fastfetch                       # твой логотип + блоки
    echo $SHELL                     # fish

  Если Hyprland не подхватил конфиг:
    hyprctl configerrors            # покажет ошибки Lua
    ls -l ~/.config/hypr/           # hyprland.lua должен быть симлинком в /nix/store

  Откат:
    sudo nixos-rebuild switch --rollback
    старые конфиги: /var/backups/nixos-theme-*
EOT
