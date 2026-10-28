{ pkgs, inputs, ... }:

let
  unstable = inputs.nixpkgs-unstable.legacyPackages.${pkgs.system};
in

{
  home.packages = with pkgs; [
    # Desenvolvimento e linha de comando
    git
    vim
    vscode
    wget
    tree
    zip
    unzip
    btop
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
  ];
}

