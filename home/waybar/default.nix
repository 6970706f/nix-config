{ pkgs, ... }:

{
  programs.waybar = {
    enable = true;

    # Mantém o CSS original separado do módulo Nix.
    style = ./style.css;

    settings = {
      mainBar = {
        # Waybar at top layer
        layer = "top";
        reload_on_style_change = true;

        # Waybar position (top|bottom|left|right)
        position = "top";

        # Height omitted to use automatic height.
        # height = 10;

        passthrough = false;
        reload_style_on_change = true;

        # Gaps between modules
        spacing = 20;

        # Gap from the top of the screen
        margin-top = 0;
        margin-left = 0;
        margin-right = 0;
        margin-bottom = 1;

        # Choose the order of the modules
        modules-left = [ "custom/icon" "hyprland/window" ];
        modules-center = [ "hyprland/workspaces" ];
        modules-right = [ "custom/recorder" "custom/mic-muted" "network" "pulseaudio" "clock" ];

        "custom/icon" = {
          format = "󰣇";
        };

        "hyprland/window" = {
          separate-outputs = true;
          # max-length = 20;
          format = "{class}";
          rewrite = {
            vesktop = "discord";
          };
        };

        # Per-module config
        "hyprland/workspaces" = {
          disable-scroll = true;
          on-click = "activate";
          format = "{icon}";
          format-icons = {
            "1" = "I";
            "2" = "II";
            "3" = "III";
            "4" = "IV";
            "5" = "V";
            "6" = "VI";
            "7" = "VII";
            "8" = "VIII";
            "9" = "IX";
            "10" = "X";
          };
        };

        pulseaudio = {
          format = "  {volume}%";
          format-muted = " Muted";
          format-icons = {
            default = [ "󰕿" "󰖀" "󰕾" ];
          };
          scroll-step = 5;
          on-click = "wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle";
          on-click-right = "pavucontrol";
          tooltip-format = "{desc} — {volume}%";
        };

        clock = {
          interval = 1;
          tooltip-format = "<tt>{calendar}</tt>";
          calendar = {
            format = {
              today = "<span color='#eed49f'><b>{}</b></span>";
            };
          };
          actions = {
            on-click-right = "shift_down";
            on-click = "shift_up";
          };
        };

        "custom/recorder" = {
          exec = ''
            [ -f /tmp/recording.state ] && echo '{"text": "⏺", "class": "recording"}' || echo '{"text": "", "class": ""}';
          '';
          return-type = "json";
          interval = "once";
          signal = 8;
        };

        "custom/mic-muted" = {
          exec = ''
            wpctl get-volume @DEFAULT_AUDIO_SOURCE@ | grep -q MUTED && echo '{"text": "󰍭", "class": "mic-muted"}' || echo '{"text": "", "class": ""}';
          '';
          return-type = "json";
          interval = "once";
          signal = 9;
        };

        network = {
          format-wifi = "󰖩";
          format-ethernet = "󰈀";
          format-disconnected = "󰖪";
          tooltip-format = "{ipAddr} — {signalStrength}%";
          on-click = "iwgtk";
        };
      };
    };
  };

  # Programs launched by Waybar's click actions.
  home.packages = with pkgs; [
    iwgtk
    pavucontrol
  ];
}
