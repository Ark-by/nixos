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
