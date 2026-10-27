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

  # Personal GTK theme and icon preferences belong to Home Manager.
  gtk = {
    enable = true;

    theme = {
      name = "Flat-Remix-GTK-White-Darkest";
      package = pkgs.flat-remix-gtk;
    };

    iconTheme = {
      name = "Flat-Remix-Black-Dark";
      package = pkgs.flat-remix-icon-theme;
    };

    colorScheme = "dark";
  };

  dconf.settings = {
    "org/gnome/desktop/interface" = {
      color-scheme = "prefer-dark";
    };
  };

  home.pointerCursor = {
    enable = true;
    name = "Bibata-Modern-Classic";
    package = pkgs.bibata-cursors;
    size = 24;

    gtk.enable = true;
    x11.enable = true;
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
