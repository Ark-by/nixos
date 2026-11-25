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
@@FLAKE@@
NIXFLAKE
sed -i "s/@USERNAME@/${USER_NAME}/g" /etc/nixos/flake.nix
if grep -q "@USERNAME@" /etc/nixos/flake.nix; then
  die "Не удалось подставить имя пользователя в flake.nix"
fi
ok "flake.nix"

# ── hypr-stack.nix ──────────────────────────────────────────────────────────
say "Раскладываю hypr-stack.nix"
cat > /etc/nixos/hypr-stack.nix <<'NIXSTACK'
@@STACK@@
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
@@HOME@@
NIXHOME
ok "home.nix"

# ── flakes для этого запуска ────────────────────────────────────────────────
subject_flakes() {
  say "Включаю flakes"
  { grep -qs '^experimental-features' /etc/nix/nix.conf \
    || printf 'experimental-features = nix-command flakes\n' >> /etc/nix/nix.conf; } 2>/dev/null || true
  export NIX_CONFIG="experimental-features = nix-command flakes"
  ok "NIX_CONFIG выставлен"
}
subject_flakes

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
