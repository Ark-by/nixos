#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
#  Этап 1 настройки: Stylix + kitty + fish + starship + fastfetch.
#
#  Запуск (из папки с этим файлом):  sudo bash theme.sh
#  Идемпотентен: бэкап делает заново, файлы перезаписывает, систему собирает.
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
SRC="$HERE/etc"

C_OK=$'\033[1;32m'; C_ERR=$'\033[1;31m'; C_HDR=$'\033[1;36m'; C_OFF=$'\033[0m'
say() { printf '\n%s▶ %s%s\n' "$C_HDR" "$*" "$C_OFF"; }
ok()  { printf '%s  ✔ %s%s\n' "$C_OK" "$*" "$C_OFF"; }
die() { printf '\n%s✘ %s%s\n' "$C_ERR" "$*" "$C_OFF" >&2; exit 1; }

trap 'printf "\n%s✘ Остановился на строке %s.%s\n" "$C_ERR" "$LINENO" "$C_OFF"' ERR

[ "$(id -u)" -eq 0 ] || die "Нужен root: sudo bash theme.sh"
command -v nixos-version >/dev/null 2>&1 || die "Это не NixOS"
[ -d "$SRC" ] || die "Рядом нет папки etc/ — скопируй всю папку, а не один скрипт"
[ -f /etc/nixos/system.nix ] || die "Нет /etc/nixos/system.nix — сначала заверши установку"

# Имя пользователя: sudo теряет $USER, поэтому берём SUDO_USER
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

say "Раскладываю flake.nix / home.nix / configs"
install -d -m 0755 /etc/nixos/configs
install -m 0644 "$SRC/flake.nix"              /etc/nixos/flake.nix
install -m 0644 "$SRC/home.nix"               /etc/nixos/home.nix
install -m 0644 "$SRC/configs/fastfetch.jsonc" /etc/nixos/configs/fastfetch.jsonc
sed -i "s/@USERNAME@/${U}/g" /etc/nixos/flake.nix
grep -q "@USERNAME@" /etc/nixos/flake.nix && die "не подставилось имя пользователя"
ok "готово"

say "Сборка (первый раз качает stylix)"
export NIX_CONFIG="experimental-features = nix-command flakes"
nixos-rebuild switch --flake /etc/nixos#nixos --show-trace

say "Готово"
ok "поколение: $(nixos-version)"
ok "бэкап: $BK"

cat <<'EOT'

  Что проверить (без перезагрузки):
    kitty                 # новый терминал: цвета + шрифт + прозрачность
    fish -c 'echo $version'   # или просто новый fish
    fastfetch             # лого NixOS и твои блоки
    starship --version    # промпт должен стать звёздным

  Если цвета не появились — перезайди в сессию (Stylix пишет файлы в ~/.config
  при активации home-manager, а kitty читает конфиг при старте).

  Откат:
    sudo nixos-rebuild switch --rollback
    старые конфиги: /var/backups/nixos-theme-*
EOT
