{ ... }:
{
  imports = [

    # Audio
    (
      # Audio services: PipeWire, ALSA, and PulseAudio compatibility.
      { ... }:

      {
        services.pipewire = {
          enable = true;
          alsa.enable = true;
          pulse.enable = true;
        };

        security.rtkit.enable = true;
      }
    )

    # Graphics and desktop portals
    (
      # Graphics support and desktop portals for Hyprland and GTK applications.
      { pkgs, ... }:

      {
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
      }
    )

    # Fonts
    (
      # System fonts for desktop applications, terminals, code editors, and emoji.
      { pkgs, ... }:

      {
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
      }
    )

    # GTK appearance
    (
      { pkgs, ... }:

      {
        programs.dconf.enable = true;

        environment.systemPackages = with pkgs; [
          gsettings-desktop-schemas
        ];

        programs.dconf.profiles.user.databases = [
          {
            settings."org/gnome/desktop/interface" = {
              gtk-theme = "Flat-Remix-GTK-White-Darkest";
              icon-theme = "Flat-Remix-Black-Dark";
              color-scheme = "prefer-dark";
            };
          }
        ];
      }
    )

    # Display manager
    (
      { ... }:

      {
        services.displayManager.sddm = {
          enable = true;
          wayland.enable = true;
        };

        services.displayManager = {
          autoLogin = {
            enable = true;
            user = "user";
          };

          defaultSession = "hyprland";
        };
      }
    )

    # Hyprland
    (
      { pkgs,  ... }:

      {
        programs.hyprland.enable = true;

        environment.systemPackages = with pkgs; [
          bibata-cursors
        ];

        environment.sessionVariables = {
          XCURSOR_THEME = "Bibata-Modern-Classic";
          XCURSOR_SIZE = "24";
        };
      }
    )

    # Thunar and file integration
    (
      { pkgs, ... }:

      {
        programs.thunar = {
          enable = true;

          plugins = [
            pkgs.thunar-archive-plugin
            pkgs.thunar-volman
          ];
        };

        programs.xfconf.enable = true;

        services.gvfs.enable = true;
        services.tumbler.enable = true;
        services.udisks2.enable = true;
      }
    )
  ];
}
