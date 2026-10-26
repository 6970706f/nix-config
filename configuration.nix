# Main entry point for the NixOS system configuration.
{ ... }:

{
  imports = [
    ./hardware-configuration.nix
    ./modules/system.nix
    ./modules/desktop.nix
  ];

  nix.settings = {
    max-jobs = 4;
    cores = 2;
  };
}
