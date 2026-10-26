{ ... }:

let
  arcTheme = "${./themes/Arc-Dark.rasi}";
in
{
  programs.rofi = {
    enable = true;
    theme = arcTheme;
  };

  xdg.configFile."rofi/utility.rasi".text = ''
    @theme "${arcTheme}"

    configuration {
      kb-row-up: "w";
      kb-row-down: "s";
      kb-accept-entry: "d";
      kb-cancel: "Escape,a";
    }

    inputbar {
      enabled: false;
    }
  '';
}
