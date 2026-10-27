{ pkgs, ... }:

{
  # Hyprland and the graphical session.
  programs.hyprland.enable = true;

  services.displayManager = {
    sddm = {
      enable = true;
      wayland.enable = true;
    };

    autoLogin = {
      enable = true;
      user = "user";
    };

    defaultSession = "hyprland";
  };

  # Graphics support and XDG portals used by Wayland/GTK applications.
  hardware.graphics.enable = true;

  xdg.portal = {
    enable = true;

    extraPortals = with pkgs; [
      xdg-desktop-portal-hyprland
      xdg-desktop-portal-gtk
    ];

    config.common.default = [
      "hyprland"
      "gtk"
    ];
  };

  # Fonts are system-wide because the graphical session and lock screen use them.
  fonts.packages = with pkgs; [
    inter
    jetbrains-mono
    liberation_ttf
    nerd-fonts.jetbrains-mono
    noto-fonts
    noto-fonts-color-emoji
    roboto
  ];

  fonts.fontconfig = {
    defaultFonts = {
      monospace = [
        "JetBrainsMono Nerd Font"
        "JetBrains Mono"
      ];

      sansSerif = [
        "Inter"
        "Roboto"
        "Noto Sans"
        "Liberation Sans"
      ];

      serif = [
        "Noto Serif"
        "Liberation Serif"
      ];

      emoji = [
        "Noto Color Emoji"
      ];
    };

    useEmbeddedBitmaps = true;
  };

  # Dconf must be enabled system-wide for Home Manager's dconf settings to work.
  programs.dconf.enable = true;

  # Keep the GSettings schemas available to GTK applications.
  environment.systemPackages = [ pkgs.gsettings-desktop-schemas ];

  # Thunar integration with archive handling, removable media and thumbnails.
  programs.thunar = {
    enable = true;

    plugins = with pkgs; [
      thunar-archive-plugin
      thunar-volman
    ];
  };

  programs.xfconf.enable = true;

  services.gvfs.enable = true;
  services.tumbler.enable = true;
  services.udisks2.enable = true;
}
