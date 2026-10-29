{
  description = "Ambiente de desenvolvimento ESP32 com ESP-IDF";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
    espidf.url = "github:hnaderi/espidf-nix";
  };

  outputs = { nixpkgs, espidf, ... }:
    let
      system = "x86_64-linux";

      pkgs = import nixpkgs {
        inherit system;
        overlays = [ espidf.overlays.default ];
      };
    in
    {
      devShells.${system}.default = espidf.lib.mkDevShell {
        inherit pkgs;

        idfVersion = "v6.1";
        idfTargets = "esp32";

        extraTools = [
          "xtensa-esp32-elf-gdb"
        ];

        extraPkgs = pkgs: with pkgs; [
          git
          clang-tools
        ];
      };
    };
}
