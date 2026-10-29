{
  description = "NixOS";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixos-unstable";
    spotifast.url = "github:crmne/spotifast/v0.14.2";

    home-manager = {
      url = "github:nix-community/home-manager/release-26.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    devShellC = {
      url = "path:./devshells/c";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    devShellESP32 = {
      url = "path:./devshells/esp32-c";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { nixpkgs, ... }@inputs: {
      nixosConfigurations.nixos = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";

      specialArgs = {
        inherit inputs;
      };

      modules = [
        ./configuration.nix

        {
          system.extraDependencies = [
            inputs.devShellC.devShells.x86_64-linux.default
            inputs.devShellESP32.devShells.x86_64-linux.default
          ];
        }

        inputs.home-manager.nixosModules.home-manager

        {
          home-manager = {
            useGlobalPkgs = true;
            useUserPackages = true;

            extraSpecialArgs = {
              inherit inputs;
            };

            backupFileExtension = "hm-backup";

            users.user = import ./home.nix;
          };
        }
      ];
    };
  };
}
