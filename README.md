# Установка стека: NixOS 26.05 + Hyprland

Готовый комплект под твою машину (Ryzen 7 2700, RTX 3050, NixOS 26.05 «Yarara»).
Запускается **один раз**, дальше только `nixos-rebuild switch` и настройка.

## Что ставится

| Слой | Что именно |
|---|---|
| Композитор | `programs.hyprland` + uwsm + XWayland |
| Экран входа | `greetd` + **HyprLogin** (из его флейка, в nixpkgs его нет) |
| Бар / обои / блокировка / idle | `waybar`, `hyprpaper`, `hyprlock`, `hypridle` |
| Терминал / шелл | `kitty`, `fish`, `starship` |
| Утилиты | `fastfetch`, `yazi`, `grim`, `slurp`, `wl-clipboard`, `cliphist` |
| Приложения | `firefox`, `zed-editor`, `rustdesk` |
| Декларативный юзер | `home-manager` (release-26.05), пока пустой — конфиги приедут из Ark-by/arch |
| Прочее | NVIDIA-драйвер (open), pipewire, порталы, шрифты (Noto + Nerd Font), zram, SSH |

Файлы после установки: `/etc/nixos/{flake,hypr-stack,home,system}.nix`
+ нетронутый `hardware-configuration.nix`.

## Требования

- NixOS 26.05, x86_64, загрузка через systemd-boot;
- интернет (первая сборка тянет ~2–3 ГБ: zed-editor, rustdesk, firefox);
- ≥ 15 ГБ свободно на `/nix`;
- 10–40 минут.

## Как перенести на NixOS-машину

Вариант А — флешка: скопировать папку `nixos-install/` целиком.

Вариант Б — сеть (если машины видят друг друга):

```sh
curl -fsSL http://<ip-винды>:8080/nixos-install.tar.gz -o /tmp/n.tar.gz
tar xzf /tmp/n.tar.gz -C /tmp
```

Вариант В — dual boot: смонтировать раздел Windows и скопировать оттуда:

```sh
sudo mkdir -p /mnt/win
sudo mount -o ro /dev/nvme0n1p3 /mnt/win   # номер раздела — свой, см. lsblk
cp -r "/mnt/win/Users/1/Documents/deepseek-harness/default-workspace/nixos-install" /tmp/
```

## Запуск

Два способа, результат одинаковый:

**А. Пошагово, командами (рекомендуется)** — последовательность шагов 0–7:

```sh
# проверка → бэкап → переименование старого конфига
# → три файла через sudo tee (flake.nix, hypr-stack.nix, home.nix)
# → sudo nixos-rebuild switch --flake /etc/nixos#nixos
```

Файлы для вставки лежат в `etc/` этой папки — их можно и просто скопировать,
тогда шаг с `sudo tee` заменяется на `cp`.

**Б. Одним скриптом** (если не хочется руками):

```sh
sudo bash install.sh          # есть флаг --safe — сразу с tuigreet
```

## После установки

```sh
sudo reboot
```

Появится HyprLogin (тема hyprlock, список сессий — Hyprland/Hyprland-uwsm).
Вход → Hyprland с дефолтным конфигом. Дальше:

```sh
bash verify.sh
```

## Если HyprLogin не завёлся

Признак: чёрный экран или возврат в TTY. Войди в `tty2` (`Ctrl+Alt+F2`) и
переключи экран входа одной строкой (в `hypr-stack.nix` уже есть переключатель):

```sh
sudo sed -i 's/useHyprlogin = true/useHyprlogin = false/' /etc/nixos/hypr-stack.nix
sudo nixos-rebuild switch --flake /etc/nixos#nixos
```

Это заменит HyprLogin на `tuigreet` (TUI-логин со списком сессий), не трогая
ни драйвер, ни пакеты. Потом разберёмся с HyprLogin отдельно — это настройка.

То же самое можно поставить сразу: `sudo bash install.sh --safe`.

## Откат

| Что | Как |
|---|---|
| Прошлое поколение системы | `sudo nixos-rebuild switch --rollback` |
| Загрузка старого поколения | меню systemd-boot при загрузке |
| Вернуть конфиги | `sudo cp -a /var/backups/nixos-<дата>/. /etc/nixos/` |
| Убрать флейк совсем | вернуть `system.nix` → `configuration.nix` и `nixos-rebuild switch` без `--flake` |

## Что НЕ делает установка

Не настраивает: hyprland.lua, waybar, hypridle, hyprpaper, hyprlock, kitty,
fish, starship, yazi, zed, fastfetch. Это следующий этап — перенос конфигов
из [Ark-by/arch](https://github.com/Ark-by/arch) в `home.nix`.
