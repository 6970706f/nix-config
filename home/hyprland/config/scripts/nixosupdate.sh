else
    log "Modo --check: sem commits novos; vou validar/compilar a configuração remota atual sem aplicá-la."
fi

if [[ "$MODE" == "apply" ]] && (( AUTO_CONFIRM == 0 )); then
    if [[ ! -t 0 ]]; then
        die "Execução sem terminal exige --yes. Revise as alterações e use --yes apenas se confiar nelas."
    fi
    printf '\nA configuração Nix pode executar código privilegiado durante a ativação. Revise o diff completo abaixo antes de continuar.\n'
    if (( HAS_UPDATE == 1 )); then
        git -C "$COMPARE" --no-pager diff "$LOCAL_COMMIT" "$REMOTE_COMMIT"
    else
        log "Sem diff de commit; o modo de verificação avaliará a versão remota atual."
    fi
    printf 'Aplicar a atualização %s? [y/N] ' "$REMOTE_COMMIT"
    read -r answer || answer=""
    [[ "$answer" == "y" || "$answer" == "Y" || "$answer" == "yes" || "$answer" == "YES" ]] || {
        log "Atualização cancelada. Nenhuma configuração foi substituída nem compilada."
        exit 0
    }
fi

CANDIDATE="$WORK/nixos"
log "Clonando a branch esperada em área temporária..."
git clone --single-branch --branch "$BRANCH" "$REPO" "$CANDIDATE" || die "Falha ao clonar a branch remota."
CLONED_COMMIT="$(git -C "$CANDIDATE" rev-parse HEAD)"
[[ "$CLONED_COMMIT" == "$REMOTE_COMMIT" ]] || die "A branch remota mudou durante a preparação. Nenhuma configuração foi substituída; execute novamente."

[[ -f "$CANDIDATE/flake.nix" && -f "$CANDIDATE/flake.lock" ]] || die "A candidata não contém flake.nix e flake.lock."
git -C "$CANDIDATE" ls-files --error-unmatch -- hardware-configuration.nix >/dev/null 2>&1 || \
    die "hardware-configuration.nix não está rastreado na candidata remota."

log "Preservando hardware-configuration.nix desta máquina na candidata..."
cp -- "$CONFIG/hardware-configuration.nix" "$CANDIDATE/hardware-configuration.nix"
TARGET_COMMIT="$CLONED_COMMIT"
EXPECTED_STATUS="$(status_of "$CANDIDATE")"
EXPECTED_HW_SHA="$(sha256sum -- "$CANDIDATE/hardware-configuration.nix" | awk '{print $1}')"

log "Validando se a flake define o host '$HOST'..."
nix eval --raw "$CANDIDATE#nixosConfigurations.${HOST}.config.system.build.toplevel.drvPath" >/dev/null || \
    die "A avaliação Nix falhou para o host '$HOST'. A configuração ativa não foi modificada."

log "Compilando a configuração candidata, sem ativá-la..."
(cd "$WORK" && nixos-rebuild build --flake "$CANDIDATE#$HOST") || \
    die "O build falhou. A configuração ativa e a geração do sistema não foram alteradas."
log "Build concluído com sucesso."

if [[ "$MODE" == "check" ]]; then
    log "CHECK concluído: validação e build passaram; /etc/nixos e as gerações do sistema não foram substituídos nem ativados."
    exit 0
fi

for path in "$BACKUP" "$STAGE" "$FAILED"; do
    [[ ! -e "$path" && ! -L "$path" ]] || die "O destino já existe; não vou sobrescrevê-lo: $path"
done

original_config_unchanged || die "A configuração local mudou enquanto o build era executado. Não vou substituir as alterações concorrentes."

log "Solicitando privilégios administrativos para preparar a troca..."
sudo -v || die "Não foi possível obter privilégios administrativos. A configuração ativa não foi modificada."

log "Preparando a candidata na mesma partição da configuração..."
sudo -n cp -a -- "$CANDIDATE" "$STAGE" || die "Não consegui preparar a candidata em $STAGE. A configuração ativa permanece no lugar."

log "Definindo propriedade root:root e permissões de leitura seguras no estágio..."
secure_config_tree "$STAGE" || die "Não consegui definir propriedade root:root e permissões seguras em $STAGE. A configuração ativa permanece no lugar."

# Verificações usadas para evitar restauração sobre alterações concorrentes.
log "Conferindo novamente a configuração candidata antes da troca..."
[[ "$(git_repo "$STAGE" rev-parse HEAD 2>/dev/null || true)" == "$TARGET_COMMIT" ]] || die "O estágio preparado não corresponde ao commit esperado."
[[ "$(status_of "$STAGE")" == "$EXPECTED_STATUS" ]] || die "O estágio mudou durante a preparação."
[[ "$(sha256sum -- "$STAGE/hardware-configuration.nix" | awk '{print $1}')" == "$EXPECTED_HW_SHA" ]] || die "hardware-configuration.nix mudou durante a preparação."
original_config_unchanged || die "A configuração local mudou durante a preparação do estágio. Nenhuma troca será feita."
sudo -v || die "Não foi possível renovar a autorização administrativa antes da troca; a configuração ativa permanece no lugar."

log "Movendo a configuração atual para o backup $BACKUP..."
[[ ! -e "$BACKUP" && ! -L "$BACKUP" ]] || die "O destino do backup apareceu durante a execução; não vou sobrescrevê-lo."
SWAP_STARTED=1
sudo -n mv -T -- "$CONFIG" "$BACKUP" || die "Não consegui preservar a configuração antiga; nenhuma atualização foi aplicada."
secure_config_tree "$BACKUP" || die "Não consegui normalizar a propriedade/permissões do backup $BACKUP. A candidata não será instalada; a recuperação será tentada."
original_tree_unchanged "$BACKUP" || die "A configuração antiga mudou durante a troca. Vou restaurá-la e não instalar a candidata."
[[ ! -e "$CONFIG" && ! -L "$CONFIG" ]] || die "$CONFIG foi recriado durante a troca. Não vou sobrescrevê-lo; a recuperação será tentada."
sudo -n mv -T -- "$STAGE" "$CONFIG" || die "Não consegui instalar a candidata; a recuperação será tentada no encerramento."

# Guarda a geração anterior para diagnóstico; a script não remove gerações.
PREVIOUS_ACTIVE_SYSTEM="$(readlink -f /run/current-system 2>/dev/null || true)"
PREVIOUS_PROFILE_SYSTEM="$(readlink -f /nix/var/nix/profiles/system 2>/dev/null || true)"

log "Aplicando a nova configuração com nixos-rebuild switch..."
sudo -v || die "Não foi possível renovar a autorização administrativa antes do switch; a recuperação será tentada."
SWITCH_STARTED=1
if ! sudo -n nixos-rebuild switch --flake "$CONFIG#$HOST"; then
    warn "nixos-rebuild switch falhou. Tentando restaurar os arquivos anteriores e reativar a configuração antiga."
    recover_after_failure 1 || true
    exit 1
fi
SWITCH_COMPLETED=1

ACTIVE_SYSTEM="$(readlink -f /run/current-system 2>/dev/null || true)"
PROFILE_SYSTEM="$(readlink -f /nix/var/nix/profiles/system 2>/dev/null || true)"
PROFILE_LINK="$(readlink /nix/var/nix/profiles/system 2>/dev/null || true)"

if [[ -z "$ACTIVE_SYSTEM" || -z "$PROFILE_SYSTEM" || "$ACTIVE_SYSTEM" != "$PROFILE_SYSTEM" || -z "$PROFILE_LINK" ]]; then
    warn "O switch retornou sucesso, mas não consegui confirmar que /run/current-system e o perfil do sistema coincidem."
    warn "Não farei rollback automático com base nesse teste isolado. A configuração anterior está preservada em $BACKUP."
    RECOVERY_DONE=1
    exit 2
fi

log "Ativação confirmada pelos links do sistema."
log "Perfil de geração: $PROFILE_LINK -> $PROFILE_SYSTEM"
log "Sistema ativo: $ACTIVE_SYSTEM"
if [[ -n "$PREVIOUS_ACTIVE_SYSTEM" ]]; then
    log "Sistema ativo antes da atualização: $PREVIOUS_ACTIVE_SYSTEM"
fi
if [[ -n "$PREVIOUS_PROFILE_SYSTEM" ]]; then
    log "Perfil do sistema antes da atualização: $PREVIOUS_PROFILE_SYSTEM"
fi

# A configuração anterior está preservada em BACKUP. Após confirmar o switch,
# erros/interrupções na retenção não devem disparar rollback automático.
SWAP_STARTED=0
RECOVERY_DONE=1

# Retenção simples: manter os backups mais recentes. Não remove diretórios .failed-*.
prune_backups() {
    local -a backups=()
    local i name
    mapfile -t backups < <(find "$CONFIG_PARENT" -mindepth 1 -maxdepth 1 -type d -name "$CONFIG_BASE.backup-*" -printf '%f\n' 2>/dev/null | LC_ALL=C sort -r)
    if ((${#backups[@]} > KEEP_BACKUPS)); then
        for ((i=KEEP_BACKUPS; i<${#backups[@]}; i++)); do
            name="${backups[i]}"
            [[ "$name" == "$CONFIG_BASE.backup-"* ]] || continue
            if ! sudo -n rm -rf -- "$CONFIG_PARENT/$name"; then
                warn "Não consegui remover backup antigo: $CONFIG_PARENT/$name"
            fi
        done
    fi
}
prune_backups

log "Atualização concluída e validação pós-switch aprovada."
log "Backup desta atualização: $BACKUP"
log "Gerações anteriores do NixOS foram preservadas pelo nixos-rebuild."
