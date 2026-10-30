{ pkgs, inputs, ... }:

let
  system = pkgs.stdenv.hostPlatform.system;

  unstable = import inputs.nixpkgs-unstable {
    inherit system;
    config.allowUnfree = true;
  };
in

{
  home.packages = with pkgs; [
    # Desenvolvimento e linha de comando
    git
    vim
    unstable.vscode
    wget
    tree
    zip
    unzip
    btop
    unstable.claude-code
    unstable.codex
    bubblewrap

    # Ambiente gráfico e ferramentas do Hyprland
    hyprlock
    nwg-look
    hyprpicker
    cliphist
    wl-clipboard
    libnotify
    brightnessctl
    glib
    hypridle
    quickshell

    # Navegadores
    librewolf
    firefox

    # Captura de tela e gravação
    wf-recorder
    slurp
    grim

    # Wallpaper e automação de entrada
    awww

    # Aplicativos pessoais
    vesktop
    seahorse
    file-roller

    # Audio/Video
    pulseaudio
    mpv

    # Spotifast vem de um input do flake
    inputs.spotifast.packages.${pkgs.stdenv.hostPlatform.system}.default
    eog
    yt-dlp
    discord
  ];
}

