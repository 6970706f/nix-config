{ config, ... }:

{
  programs.zsh = {
    enable = true;
    enableCompletion = true;

    autosuggestion.enable = true;
    syntaxHighlighting.enable = true;

    shellAliases = {
      rebuild = "sudo nixos-rebuild switch --flake /etc/nixos#nixos";
      upgrade = "nix flake update --flake /etc/nixos";
      update = "${config.home.homeDirectory}/.config/hypr/scripts/nixos-update";
    };

    history = {
      size = 10000;
      ignoreAllDups = true;
      ignorePatterns = [
        "rm *"
        "pkill *"
        "cp *"
      ];
    };

    oh-my-zsh = {
      enable = true;
      theme = "kardan";

      plugins = [
        "git"
        "sudo"
        "command-not-found"
        "z"
        "extract"
        "colored-man-pages"
      ];
    };
  };
}
