{ config, lib, pkgs, ... }:

{
  programs.quickshell = {
    enable = true;
    package = pkgs.quickshell;
    systemd.enable = true;
  };

  # Instala os arquivos diretamente em ~/.config/quickshell, para que `qs`
  # use shell.qml como configuração padrão e `qs ipc call` encontre o IPC.
  xdg.configFile."quickshell".source = ./config;
}
