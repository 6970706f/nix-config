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
      espa = "source ~/.espressif/tools/activate_idf_v6.1.sh";
      espd = "source ~/.espressif/tools/deactivate_idf_v6.1.sh";
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
