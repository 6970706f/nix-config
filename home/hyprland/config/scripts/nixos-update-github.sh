#!/usr/bin/env bash
set -Eeuo pipefail

REPO="git@github.com:6970706f/nix-config.git"
CONFIG="/etc/nixos"
HOST="nixos"

STAMP="$(date +%Y%m%d-%H%M%S)-$$"
BACKUP="/etc/nixos.backup-$STAMP"
FAILED="/etc/nixos.failed-$STAMP"
WORK="$(mktemp -d)"

cleanup() {
    if [[ ! -e "$CONFIG" && ! -L "$CONFIG" && -d "$BACKUP" ]]; then
        echo "WARNING: Configuration directory missing. Restoring backup..."
        if ! sudo mv -- "$BACKUP" "$CONFIG"; then
            echo "CRITICAL: Could not restore backup: $BACKUP"
        fi
    fi

    rm -rf -- "$WORK"
}

trap cleanup EXIT

restore_config_files() {
    echo "==> Restoring previous configuration files..."

    if sudo test -e "$CONFIG" || sudo test -L "$CONFIG"; then
        if ! sudo mv -- "$CONFIG" "$FAILED"; then
            echo "CRITICAL: Could not move failed configuration."
            echo "Backup location: $BACKUP"
            return 1
        fi
    fi

    if ! sudo mv -- "$BACKUP" "$CONFIG"; then
        echo "CRITICAL: Could not restore previous configuration."
        echo "Backup location: $BACKUP"
        return 1
    fi

    echo "Previous configuration files restored."
}

recover_system() {
    if ! restore_config_files; then
        return 1
    fi

    echo "==> Reactivating previous system configuration..."

    if sudo nixos-rebuild switch --flake "$CONFIG#$HOST"; then
        echo "Previous system configuration reactivated."
        return 0
    fi

    echo "WARNING: Reactivation failed. Trying generation rollback..."

    if sudo nixos-rebuild --rollback switch; then
        echo "System generation rollback completed."
        return 0
    fi

    echo "CRITICAL: Automatic recovery failed."
    echo "Select a previous generation from the boot menu if necessary."
    return 1
}

if [[ ! -d "$CONFIG" || ! -f "$CONFIG/flake.nix" ]]; then
    echo "Error: NixOS configuration or flake.nix not found."
    exit 1
fi

if [[ ! -f "$CONFIG/hardware-configuration.nix" ]]; then
    echo "Error: hardware-configuration.nix not found."
    exit 1
fi

cp -- "$CONFIG/hardware-configuration.nix" \
    "$WORK/hardware-configuration.nix"

echo "==> Cloning configuration from GitHub..."

git clone "$REPO" "$WORK/nixos"

if [[ ! -f "$WORK/nixos/flake.nix" ||
      ! -f "$WORK/nixos/flake.lock" ]]; then
    echo "Error: flake.nix or flake.lock is missing from the repository."
    exit 1
fi

if ! git -C "$WORK/nixos" ls-files \
    --error-unmatch -- hardware-configuration.nix >/dev/null 2>&1; then
    echo "Error: hardware-configuration.nix must be tracked by Git."
    exit 1
fi

echo "==> Preserving local hardware configuration..."

cp -- "$WORK/hardware-configuration.nix" \
    "$WORK/nixos/hardware-configuration.nix"

echo "==> Building and validating configuration..."

if ! (cd "$WORK" &&
    sudo nixos-rebuild build --flake "$WORK/nixos#$HOST"); then
    echo "Error: Build failed. Existing configuration was not replaced."
    exit 1
fi

echo "==> Backing up current configuration..."

if ! sudo mv -- "$CONFIG" "$BACKUP"; then
    echo "Error: Could not back up current configuration."
    exit 1
fi

echo "==> Installing new configuration..."

if ! sudo mv -- "$WORK/nixos" "$CONFIG"; then
    echo "Error: Failed to install new configuration."

    if restore_config_files; then
        echo "Previous files restored. System was not switched."
    else
        echo "CRITICAL: Manual recovery may be required."
    fi

    exit 1
fi

echo "==> Applying new system configuration..."

if ! sudo nixos-rebuild switch --flake "$CONFIG#$HOST"; then
    echo "Error: Switch failed. Attempting recovery..."

    if recover_system; then
        echo "Update failed, but recovery succeeded."
    else
        echo "CRITICAL: Recovery was incomplete."
        echo "Backup: $BACKUP"
        echo "Failed configuration: $FAILED"
    fi

    exit 1
fi

echo "==> System update completed successfully."
echo "Previous configuration backup: $BACKUP"

