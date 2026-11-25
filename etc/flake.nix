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
