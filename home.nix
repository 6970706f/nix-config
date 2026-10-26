{ pkgs, ... }:

{
  imports = [
    ./home/hyprland
    ./home/waybar
    ./home/rofi
    ./home/zsh
    ./home/packages.nix
    ./home/kitty
    ./home/dunst
  ];

  home.username = "user";
  home.homeDirectory = "/home/user";

  home.stateVersion = "26.05";

  home.pointerCursor = {
    enable = true;
    name = "Bibata-Modern-Classic";
    package = pkgs.bibata-cursors;
    size = 24;

    gtk.enable = true;
    x11.enable = true;
  };

  home.sessionVariables = {
    XCURSOR_THEME = "Bibata-Modern-Classic";
    XCURSOR_SIZE = "24";
  };

  xdg.mimeApps = {
    enable = true;

    defaultApplications = {
      "text/html" = "librewolf.desktop";
      "application/xhtml+xml" = "librewolf.desktop";
      "x-scheme-handler/http" = "librewolf.desktop";
      "x-scheme-handler/https" = "librewolf.desktop";
      "x-scheme-handler/about" = "librewolf.desktop";
      "x-scheme-handler/unknown" = "librewolf.desktop";
    };
  };
}
