#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
#  Проверки после первой перезагрузки.  Запуск:  bash verify.sh
#  Ничего не меняет — только смотрит и печатает. Запускай из Hyprland-терминала
#  (kitty), тогда проверятся ещё hyprctl и звук.
# ─────────────────────────────────────────────────────────────────────────────
set -u

C_OK=$'\033[1;32m'; C_ERR=$'\033[1;31m'; C_HDR=$'\033[1;36m'; C_OFF=$'\033[0m'
ok()   { printf '%s  ✔ %s%s\n' "$C_OK" "$*" "$C_OFF"; }
bad()  { printf '%s  ✘ %s%s\n' "$C_ERR" "$*" "$C_OFF"; }
info() { printf '    %s\n' "$*"; }
head2(){ printf '\n%s▶ %s%s\n' "$C_HDR" "$*" "$C_OFF"; }
have() { command -v "$1" >/dev/null 2>&1; }

head2 "Система"
nixos-version 2>/dev/null || bad "nixos-version не отвечает"
info "ядро: $(uname -r)"
info "сессия: ${XDG_SESSION_TYPE:-нет} / ${XDG_CURRENT_DESKTOP:-нет}"

head2 "Пакеты стека"
missing=0
for b in Hyprland hyprctl start-hyprland hyprlogin hypridle hyprpaper hyprlock \
         waybar kitty fish starship fastfetch yazi zeditor firefox rustdesk \
         grim slurp wl-copy cliphist; do
  if have "$b"; then
    ok "$b"
  else
    bad "$b — НЕ найден"
    missing=$((missing + 1))
  fi
done
printf '  ── не найдено: %s\n' "$missing"

head2 "Экран входа (greetd + HyprLogin)"
systemctl is-enabled --quiet greetd && ok "greetd включён в автозапуск" || bad "greetd не включён"
if systemctl is-active --quiet greetd; then
  ok "greetd активен"
else
  info "greetd сейчас не активен (нормально: ты уже вошёл, greeter завершился)"
fi
if [ -f /etc/greetd/config.toml ]; then
  info "сессия: $(grep -o 'start-hyprland.*' /etc/greetd/config.toml | head -1)"
else
  bad "нет /etc/greetd/config.toml"
fi
[ -f /etc/hyprlogin/hyprlogin.conf ] && ok "конфиг /etc/hyprlogin/hyprlogin.conf" || bad "нет /etc/hyprlogin/hyprlogin.conf"

head2 "NVIDIA"
if have nvidia-smi; then
  nvidia-smi --query-gpu=name,driver_version --format=csv,noheader 2>/dev/null | sed 's/^/    /' || bad "nvidia-smi не отвечает"
  lsmod | grep -q '^nvidia ' && ok "модуль nvidia загружен" || bad "модуль nvidia не загружен"
else
  bad "nvidia-smi отсутствует"
fi
[ -e /dev/dri/card0 ] && ok "/dev/dri/card0 есть" || bad "нет /dev/dri/card0"
info "группы: $(id -nG "$(id -un)")"

head2 "Hyprland"
if [ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]; then
  hyprctl version 2>/dev/null | head -3 | sed 's/^/    /'
  hyprctl monitors 2>/dev/null | grep -E '^(Monitor|.*[0-9]+x[0-9]+)' | head -4 | sed 's/^/    /'
else
  info "не внутри сессии Hyprland — проверь вручную: hyprctl version"
fi

head2 "Звук"
systemctl --user is-active --quiet pipewire && ok "pipewire" || bad "pipewire не активен"
systemctl --user is-active --quiet wireplumber && ok "wireplumber" || bad "wireplumber не активен"

head2 "Оболочка"
info "SHELL=$SHELL"
info "passwd: $(getent passwd "$(id -un)" | cut -d: -f7)"
[ "${SHELL##*/}" = "fish" ] && ok "fish по умолчанию" || info "fish не логин-шелл: chsh -s $(command -v fish)"

head2 "Диск"
df -h / 2>/dev/null | sed 's/^/    /'
