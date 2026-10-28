{ config, pkgs, ... }:

{
  services.dunst = {
    enable = true;

    settings = {
      global = {
        monitor = 0;
        follow = "mouse";
        origin = "bottom-right";
        offset = "20x20";
        width = "(260, 340)";
        height = "(0, 140)";

        # Appearance
        font = "JetBrainsMono Nerd Font ExtraLight 10";
        padding = 14;
        horizontal_padding = 16;
        text_icon_padding = 0;
        frame_width = 1;
        corner_radius = 0;
        gap_size = 8;
        separator_height = 0;
        transparency = 0;

        # Icons and indicators
        icon_position = "off";
        show_indicators = false;
        indicate_hidden = true;
        sort = true;
        stack_duplicates = true;
        hide_duplicate_count = false;

        # Text
        markup = "full";
        format = "<b>%s</b>\\n%b";
        alignment = "left";
        vertical_alignment = "center";
        word_wrap = true;
        ellipsize = "end";
        ignore_newline = false;
        show_age_threshold = -1;

        # Progress bar
        progress_bar = true;
        progress_bar_height = 4;
        progress_bar_frame_width = 0;
        progress_bar_min_width = 150;
        progress_bar_max_width = 300;

        # Interaction
        mouse_left_click = "close_current";
        mouse_middle_click = "do_action, close_current";
        mouse_right_click = "close_all";
        sticky_history = true;
        history_length = 20;
      };

      urgency_low = {
        background = "#000000";
        foreground = "#8a8a8a";
        frame_color = "#1f1f1f";
        highlight = "#8a8a8a";
        timeout = 4;
      };

      urgency_normal = {
        background = "#000000";
        foreground = "#ffffff";
        frame_color = "#ffffff";
        highlight = "#ffffff";
        timeout = 6;
      };

      urgency_critical = {
        background = "#ffffff";
        foreground = "#000000";
        frame_color = "#ffffff";
        highlight = "#000000";
        timeout = 0;
      };
    };
  };
}