{ pkgs, ... }:

{
  # Hyprland itself should remain enabled by the NixOS module in configuration.nix.
  # Home Manager manages this user's configuration, without installing a second
  # Hyprland/XDPH build that could mismatch the system package.
  wayland.windowManager.hyprland = {
    enable = true;
    package = null;
    portalPackage = null;
    configType = "lua";

    # Home Manager generates ~/.config/hypr/hyprland.lua; these are the user's
    # original module loading order and names.
    extraConfig = ''
      require("conf.monitors")
      require("conf.environment")
      require("conf.autostart")
      require("conf.appearance")
      require("conf.input")
      require("conf.keybinds")
      require("conf.windowrules")
    '';
  };

  # Used by the lock-screen song label and existing media keybindings.
  home.packages = [ pkgs.playerctl ];

  # Lua configuration modules.
  xdg.configFile = {
    "hypr/conf/monitors.lua".source = ./config/conf/monitors.lua;
    "hypr/conf/environment.lua".source = ./config/conf/environment.lua;
    "hypr/conf/autostart.lua".source = ./config/conf/autostart.lua;
    "hypr/conf/appearance.lua".source = ./config/conf/appearance.lua;
    "hypr/conf/input.lua".source = ./config/conf/input.lua;
    "hypr/conf/keybinds.lua".source = ./config/conf/keybinds.lua;
    "hypr/conf/windowrules.lua".source = ./config/conf/windowrules.lua;

    # Hyprland companion configurations.
    "hypr/hyprlock.conf".source = ./config/hyprlock.conf;
    "hypr/hypridle.conf".source = ./config/hypridle.conf;

    # Media assets referenced by hyprlock.conf and mute.sh.
    "hypr/media/hyprlock.png".source = ./config/media/hyprlock.png;
    "hypr/media/mic-mute.mp3".source = ./config/media/mic-mute.mp3;
    "hypr/media/mic-unmute.mp3".source = ./config/media/mic-unmute.mp3;

    # Scripts must retain executable permissions in ~/.config/hypr/scripts.
    "hypr/scripts/autoclick.sh" = {
      source = ./config/scripts/autoclick.sh;
      executable = true;
    };
    "hypr/scripts/toggleaudio.sh" = {
      source = ./config/scripts/toggleaudio.sh;
      executable = true;
    };
    "hypr/scripts/rofi-menu.sh" = {
      source = ./config/scripts/rofi-menu.sh;
      executable = true;
    };
    "hypr/scripts/record.sh" = {
      source = ./config/scripts/record.sh;
      executable = true;
    };
    "hypr/scripts/print.sh" = {
      source = ./config/scripts/print.sh;
      executable = true;
    };
    "hypr/scripts/nextwallpaper.sh" = {
      source = ./config/scripts/nextwallpaper.sh;
      executable = true;
    };
    "hypr/scripts/mute.sh" = {
      source = ./config/scripts/mute.sh;
      executable = true;
    };
    "hypr/scripts/songdetail.sh" = {
      source = ./config/scripts/songdetail.sh;
      executable = true;
    };
  };
}
