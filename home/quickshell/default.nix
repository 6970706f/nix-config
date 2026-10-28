{ config, lib, pkgs, ... }:

{
  programs.quickshell = {
    enable = true;
    package = pkgs.quickshell;
    systemd.enable = true;
  };

  xdg.configFile."quickshell".source = ./config;
}
