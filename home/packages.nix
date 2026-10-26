{ pkgs, inputs, ... }:

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

    # Ambiente gráfico e ferramentas do Hyprland
    hyprlock
    kitty
    nwg-look
    hyprpicker
    cliphist
    wl-clipboard
    libnotify
    brightnessctl
    glib
    hypridle

    # Temas e ícones
    flat-remix-gtk
    flat-remix-icon-theme

    # Navegadores
    librewolf
    firefox

    # Captura de tela e gravação
    wf-recorder
    slurp
    grim

    # Wallpaper e automação de entrada
    awww
    ydotool

    # Aplicativos pessoais
    vesktop
    seahorse
    file-roller

    # Audio
    pulseaudio

    # Spotifast vem de um input do flake
    inputs.spotifast.packages.${pkgs.stdenv.hostPlatform.system}.default

    brightnessctl
    glib
    hypridle
    dunst
  ];
}
