{ config, lib, pkgs, ... }:

{
  xdg.configFile."matugen".source = ./config;
}
