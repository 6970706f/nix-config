{ pkgs, ... }:

{
  # Boot
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # Localization and keyboard
  time.timeZone = "America/Sao_Paulo";

  i18n.defaultLocale = "en_US.UTF-8";

  i18n.extraLocaleSettings = {
    LC_ADDRESS = "pt_BR.UTF-8";
    LC_IDENTIFICATION = "pt_BR.UTF-8";
    LC_MEASUREMENT = "pt_BR.UTF-8";
    LC_MONETARY = "pt_BR.UTF-8";
    LC_NAME = "pt_BR.UTF-8";
    LC_NUMERIC = "pt_BR.UTF-8";
    LC_PAPER = "pt_BR.UTF-8";
    LC_TELEPHONE = "pt_BR.UTF-8";
    LC_TIME = "pt_BR.UTF-8";
  };

  services.xserver.xkb = {
    layout = "us";
    variant = "";
  };

  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 30d";
  };

  nix.optimise = {
    automatic = true;
    dates = [ "weekly" ];
  };

  # Networking
  networking.hostName = "nixos";
  networking.networkmanager.enable = true;

  # Nix configuration
  nixpkgs.config.allowUnfree = true;
  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];

  # Applications and system services
  programs.appimage = {
    enable = true;
    binfmt = true;
  };

  virtualisation.libvirtd.enable = true;

  programs.steam.enable = true;
  programs.ydotool.enable = true;
  programs.virt-manager.enable = true;

  services.flatpak.enable = true;
  services.gnome.gnome-keyring.enable = true;

  # Shell
  programs.zsh.enable = true;

  # User account
  users.users.user = {
    isNormalUser = true;
    description = "user";

    extraGroups = [
      "networkmanager"
      "wheel"
      "ydotool"
      "libvirtd"
    ];

    shell = pkgs.zsh;
  };

  # Keep unchanged when upgrading NixOS
  system.stateVersion = "26.05";
}

