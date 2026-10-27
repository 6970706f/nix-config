#Main entry point for the NixOS system configuration.
{ ... }:

{
  imports = [
    ./hardware-configuration.nix
    ./modules/system.nix
    ./modules/desktop.nix
    ./modules/audio.nix
  ];
}
