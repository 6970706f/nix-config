#!/usr/bin/env bash
set -Eeuo pipefail

# Atualiza a configuração NixOS a partir do repositório esperado.
# Execute como usuário normal, não com sudo: Git/SSH deve usar a chave do usuário.

REPO="git@github.com:6970706f/nix-config.git"
BRANCH="main"
CONFIG="${NIXOS_CONFIG_DIR:-/etc/nixos}"
HOST="${NIXOS_HOST:-nixos}"
KEEP_BACKUPS="${NIXOS_BACKUP_KEEP:-5}"
MODE="apply"
AUTO_CONFIRM=0

usage() {
    cat <<'USAGE'
Uso:
  nixos-update-github-improved.sh [--check] [--yes]

  --check  Verifica a origem/branch, busca o remoto, valida e compila a
           configuração candidata, sem substituir /etc/nixos nem ativá-la.
  --yes    Não pergunta confirmação antes de aplicar a atualização.
  --help   Mostra esta ajuda.

Variáveis opcionais:
  NIXOS_CONFIG_DIR  Diretório da configuração (padrão: /etc/nixos)
  NIXOS_HOST        Nome do host na flake (padrão: nixos)
  NIXOS_BACKUP_KEEP Número de backups a manter (padrão: 5; mínimo: 1)
USAGE
}

log() { printf '[%s] %s\n' "$(date '+%F %T')" "$*"; }
die() { log "ERRO: $*" >&2; exit 1; }
warn() { log "AVISO: $*" >&2; }

while (($#)); do
    case "$1" in
        --check) MODE="check" ;;
        --yes) AUTO_CONFIRM=1 ;;
        --help|-h) usage; exit 0 ;;
        *) usage >&2; die "Argumento desconhecido: $1" ;;
    esac
    shift
done

# A flake pode conter código executado com privilégios durante a ativação.
# Mantenha Git/SSH no usuário real e use sudo somente nas etapas privilegiadas.
(( EUID != 0 )) || die "Não execute com sudo. Execute como usuário normal com acesso SSH ao GitHub."
[[ "$HOST" =~ ^[A-Za-z0-9_-]+$ ]] || die "Nome de host inválido: $HOST"
[[ "$CONFIG" == /* ]] || die "NIXOS_CONFIG_DIR precisa ser um caminho absoluto."
[[ "$KEEP_BACKUPS" =~ ^[0-9]+$ ]] || die "NIXOS_BACKUP_KEEP precisa ser um inteiro >= 1."
KEEP_BACKUPS=$((10#$KEEP_BACKUPS))
(( KEEP_BACKUPS >= 1 )) || die "NIXOS_BACKUP_KEEP precisa ser um inteiro >= 1."

for cmd in git nix nixos-rebuild sudo flock mktemp sha256sum find sort readlink grep awk date dirname basename cp mv rm cat chmod chown; do
    command -v "$cmd" >/dev/null 2>&1 || die "Dependência necessária não encontrada: $cmd"
done

[[ -d "$CONFIG" && ! -L "$CONFIG" ]] || die "Diretório inexistente ou symlink não permitido: $CONFIG"
CONFIG="$(cd -- "$CONFIG" && pwd -P)"
[[ -f "$CONFIG/flake.nix" && -f "$CONFIG/flake.lock" ]] || die "flake.nix ou flake.lock não encontrado em $CONFIG"
[[ -r "$CONFIG/flake.nix" && -r "$CONFIG/flake.lock" ]] || die "flake.nix e flake.lock precisam ser legíveis pelo usuário que executa o script."
[[ -f "$CONFIG/hardware-configuration.nix" && ! -L "$CONFIG/hardware-configuration.nix" ]] || die "hardware-configuration.nix não encontrado ou não é um arquivo regular."
[[ -r "$CONFIG/hardware-configuration.nix" ]] || die "hardware-configuration.nix não é legível pelo usuário que executa o script."

# Executa apenas comandos Git de leitura (ou exportação para WORK) contra o
# repositório ativo. safe.directory contorna a proteção de ownership do Git;
# GIT_OPTIONAL_LOCKS=0 evita a atualização opcional do índice durante leituras.
# Isso NÃO concede permissão de leitura: os diretórios/arquivos .git precisam
# permitir leitura e travessia para o usuário que executa o script.
git_repo() {
    local repo="$1"
    shift
    GIT_OPTIONAL_LOCKS=0 git -c safe.directory= -c "safe.directory=$repo" -C "$repo" "$@"
}

if ! git_repo "$CONFIG" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    die "Não consegui ler o repositório Git em $CONFIG. safe.directory cobre o ownership, mas não as permissões: garanta leitura dos metadados .git e travessia dos diretórios."
fi

# Lock fora do repositório para não sujar o estado Git. O lock permanece aberto
# até o processo terminar e é liberado pelo kernel em qualquer saída normal.
LOCK_DIR="${XDG_RUNTIME_DIR:-/tmp}"
LOCK_FILE="$LOCK_DIR/nixos-update-github-${UID}.lock"
umask 077
[[ -d "$LOCK_DIR" && -w "$LOCK_DIR" ]] || die "Diretório do lock indisponível: $LOCK_DIR"
[[ ! -L "$LOCK_FILE" ]] || die "O arquivo de lock é um symlink inesperado: $LOCK_FILE"
exec 9>>"$LOCK_FILE"
flock -n 9 || die "Outra instância deste script já está executando."
umask 022

STAMP="$(date +%Y%m%d-%H%M%S)-$$"
CONFIG_PARENT="$(dirname -- "$CONFIG")"
CONFIG_BASE="$(basename -- "$CONFIG")"
BACKUP="${CONFIG}.backup-${STAMP}"
STAGE="${CONFIG}.stage-${STAMP}"
FAILED="${CONFIG}.failed-${STAMP}"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/nixos-update.XXXXXXXX")"
WORK="$(cd "$WORK" && pwd -P)"

SWAP_STARTED=0
SWITCH_STARTED=0
SWITCH_COMPLETED=0
RECOVERY_DONE=0
EXPECTED_STATUS=""
EXPECTED_HW_SHA=""
ORIGINAL_STATUS=""
ORIGINAL_HW_SHA=""
TARGET_COMMIT=""
LOCAL_COMMIT=""
REMOTE_COMMIT=""
PREVIOUS_ACTIVE_SYSTEM=""
PREVIOUS_PROFILE_SYSTEM=""

log "Configuração: $CONFIG"
log "Repositório esperado: $REPO"
log "Branch esperada: $BRANCH"
log "Host da flake: $HOST"

cleanup() {
    local rc=$?
    trap - EXIT
    # Evita que uma segunda interrupção inicie uma segunda recuperação.
    trap '' INT TERM

    if (( rc != 0 && SWAP_STARTED == 1 && RECOVERY_DONE == 0 )); then
        if (( SWITCH_COMPLETED == 1 )); then
            RECOVERY_DONE=1
            warn "O switch terminou com sucesso, mas a execução foi interrompida durante a verificação pós-switch. Não farei rollback automático; a configuração anterior está preservada em $BACKUP."
        else
            log "A execução falhou após iniciar a troca. Verificando se a restauração é segura..."
            recover_after_failure "$SWITCH_STARTED" || true
        fi
    fi

    if [[ -e "$STAGE" || -L "$STAGE" ]]; then
        if ! sudo -n rm -rf -- "$STAGE"; then
            warn "Não consegui remover o diretório temporário $STAGE; remova-o manualmente se estiver vazio/inativo."
        fi
    fi

    if [[ -n "${WORK:-}" && -d "$WORK" ]]; then
        cd / || true
        rm -rf -- "$WORK" || warn "Não consegui remover o diretório temporário $WORK."
    fi

    exit "$rc"
}

trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

# O processo pode ter sido iniciado de dentro de /etc/nixos; sair desse diretório
# evita continuar com o cwd apontando para o backup após a troca.
cd "$WORK"

status_of() {
    git_repo "$1" status --short --untracked-files=all --ignored=matching
}

check_local_state() {
    local line xy path state
    state="$(status_of "$CONFIG")" || die "Não foi possível verificar o estado do repositório."

    while IFS= read -r line; do
        [[ -n "$line" ]] || continue
        xy="${line:0:2}"
        path="${line:3}"

        if [[ "$xy" == '!!' ]]; then
            die "Há arquivo/diretório ignorado pelo Git que seria retirado da configuração ativa: $path. Mova-o ou revise-o antes de atualizar."
        fi

        # Este arquivo é específico da máquina. O script o copia explicitamente
        # para a candidata; por isso, essa alteração não será descartada.
        if [[ "$path" == "hardware-configuration.nix" ]]; then
            continue
        fi

        die "O repositório contém alteração local, arquivo não rastreado ou mudança staged: '$line'. Nada foi substituído. Revise/commite essas mudanças ou mova-as para fora de $CONFIG."
    done <<< "$state"

    git_repo "$CONFIG" ls-files --error-unmatch -- hardware-configuration.nix >/dev/null 2>&1 || \
        die "hardware-configuration.nix precisa estar rastreado pelo Git para que a preservação local seja previsível."
}

candidate_is_unchanged() {
    local head branch origin status hw_sha
    [[ -d "$CONFIG" && ! -L "$CONFIG" ]] || return 1
    head="$(git_repo "$CONFIG" rev-parse HEAD 2>/dev/null)" || return 1
    [[ "$head" == "$TARGET_COMMIT" ]] || return 1
    branch="$(git_repo "$CONFIG" branch --show-current 2>/dev/null)" || return 1
    [[ "$branch" == "$BRANCH" ]] || return 1
    origin="$(git_repo "$CONFIG" remote get-url origin 2>/dev/null)" || return 1
    [[ "$origin" == "$REPO" ]] || return 1
    status="$(status_of "$CONFIG" 2>/dev/null)" || return 1
    [[ "$status" == "$EXPECTED_STATUS" ]] || return 1
    hw_sha="$(sha256sum -- "$CONFIG/hardware-configuration.nix" 2>/dev/null | awk '{print $1}')" || return 1
    [[ "$hw_sha" == "$EXPECTED_HW_SHA" ]] || return 1
}

original_tree_unchanged() {
    local tree="$1" head branch origin status hw_sha
    [[ -d "$tree" && ! -L "$tree" ]] || return 1
    head="$(git_repo "$tree" rev-parse HEAD 2>/dev/null)" || return 1
    [[ "$head" == "$LOCAL_COMMIT" ]] || return 1
    branch="$(git_repo "$tree" branch --show-current 2>/dev/null)" || return 1
    [[ "$branch" == "$BRANCH" ]] || return 1
    origin="$(git_repo "$tree" remote get-url origin 2>/dev/null)" || return 1
    [[ "$origin" == "$REPO" ]] || return 1
    status="$(status_of "$tree" 2>/dev/null)" || return 1
    [[ "$status" == "$ORIGINAL_STATUS" ]] || return 1
    hw_sha="$(sha256sum -- "$tree/hardware-configuration.nix" 2>/dev/null | awk '{print $1}')" || return 1
    [[ "$hw_sha" == "$ORIGINAL_HW_SHA" ]] || return 1
}

original_config_unchanged() { original_tree_unchanged "$CONFIG"; }

# Padroniza uma árvore de configuração para /etc/nixos:
# - todos os objetos ficam root:root;
# - diretórios ficam 0755;
# - arquivos comuns ficam 0644 e arquivos com bit executável ficam 0755;
# - symlinks são preservados, sem alterar os destinos apontados.
# Isso mantém a árvore legível para Git/Nix como usuário normal, mas não gravável
# por ele. É usado tanto no estágio novo quanto no backup antigo antes de restaurá-lo.
secure_config_tree() {
    local tree="$1" bad
    sudo -n chown -R root:root -- "$tree" || return 1
    sudo -n find "$tree" -type d -exec chmod 755 -- {} + || return 1
    sudo -n find "$tree" -type f -perm /111 -exec chmod 755 -- {} + || return 1
    sudo -n find "$tree" -type f ! -perm /111 -exec chmod 644 -- {} + || return 1

    # Verifica o resultado em vez de presumir que os comandos concluíram o trabalho.
    bad="$(sudo -n find "$tree" \( ! -user root -o ! -group root \) -print -quit)" || return 1
    [[ -z "$bad" ]] || { warn "Há arquivos que não pertencem a root:root em $tree: $bad"; return 1; }
    bad="$(sudo -n find "$tree" -type d ! -perm 0755 -print -quit)" || return 1
    [[ -z "$bad" ]] || { warn "Há diretórios com permissões inesperadas em $tree: $bad"; return 1; }
    bad="$(sudo -n find "$tree" -type f \( -perm /111 ! -perm 0755 -o ! -perm /111 ! -perm 0644 \) -print -quit)" || return 1
    [[ -z "$bad" ]] || { warn "Há arquivos com permissões inesperadas em $tree: $bad"; return 1; }
    return 0
}

restore_previous_files() {
    if [[ ! -d "$BACKUP" ]]; then
        if [[ -d "$CONFIG" && ! -L "$CONFIG" ]]; then
            # A configuração original ainda está no lugar; a movimentação não ocorreu.
            SWAP_STARTED=0
            RECOVERY_DONE=1
            log "A configuração original ainda está no lugar; nenhuma restauração era necessária."
            return 0
        fi
        warn "A configuração anterior não está disponível em $BACKUP. Intervenção manual necessária."
        return 1
    fi

    if [[ ! -e "$CONFIG" && ! -L "$CONFIG" ]]; then
        if ! secure_config_tree "$BACKUP"; then
            warn "Não consegui verificar a propriedade/permissões do backup $BACKUP. Não vou restaurá-lo automaticamente."
            return 1
        fi
        if sudo -n mv -T -- "$BACKUP" "$CONFIG"; then
            SWAP_STARTED=0
            RECOVERY_DONE=1
            log "Arquivos anteriores restaurados; a candidata ainda não estava instalada."
            return 0
        fi
        warn "Não consegui restaurar a configuração de $BACKUP."
        return 1
    fi

    if ! candidate_is_unchanged; then
        warn "A configuração ativa mudou desde a instalação da candidata. Não vou sobrescrevê-la durante a recuperação."
        warn "Configuração atual: $CONFIG | configuração anterior: $BACKUP"
        return 1
    fi

    if [[ -e "$FAILED" || -L "$FAILED" ]]; then
        warn "O destino de diagnóstico já existe; não vou sobrescrevê-lo: $FAILED"
        return 1
    fi

    if ! sudo -n mv -T -- "$CONFIG" "$FAILED"; then
        warn "Não consegui mover a candidata com falha para $FAILED."
        return 1
    fi
    if ! sudo -n mv -T -- "$BACKUP" "$CONFIG"; then
        warn "A candidata foi preservada em $FAILED, mas não consegui restaurar $BACKUP."
        return 1
    fi

    SWAP_STARTED=0
    RECOVERY_DONE=1
    log "Arquivos de configuração anteriores restaurados. Candidata preservada em $FAILED."
    return 0
}

recover_after_failure() {
    local should_reactivate="${1:-0}"
    RECOVERY_DONE=1

    if ! restore_previous_files; then
        warn "A restauração automática foi interrompida para evitar sobrescrever dados possivelmente alterados por outro processo."
        return 1
    fi

    if [[ "$should_reactivate" == "1" ]]; then
        log "Tentando reativar a configuração anterior restaurada..."
        if sudo -n nixos-rebuild switch --flake "$CONFIG#$HOST"; then
            local active profile
            active="$(readlink -f /run/current-system 2>/dev/null || true)"
            profile="$(readlink -f /nix/var/nix/profiles/system 2>/dev/null || true)"
            if [[ -n "$active" && "$active" == "$profile" ]]; then
                log "Configuração anterior reativada; os links do sistema ativo e do perfil coincidem."
                return 0
            fi
            warn "O comando de reativação terminou, mas não consegui confirmar que os links do sistema coincidem."
        else
            warn "Não foi possível reativar automaticamente a configuração anterior."
        fi
        warn "Os arquivos anteriores foram restaurados, mas a reativação não foi confirmada. Avalie: sudo nixos-rebuild --rollback switch"
        warn "Se o sistema não iniciar, selecione uma geração anterior no menu de inicialização."
        return 1
    fi

    log "A troca falhou antes de iniciar o switch; os arquivos anteriores foram restaurados."
    return 0
}

check_local_state
ORIGINAL_STATUS="$(status_of "$CONFIG")"
ORIGINAL_HW_SHA="$(sha256sum -- "$CONFIG/hardware-configuration.nix" | awk '{print $1}')"

LOCAL_BRANCH="$(git_repo "$CONFIG" branch --show-current)"
[[ "$LOCAL_BRANCH" == "$BRANCH" ]] || die "Branch local inesperada: '$LOCAL_BRANCH'; esperado '$BRANCH'."
LOCAL_ORIGIN="$(git_repo "$CONFIG" remote get-url origin 2>/dev/null || true)"
[[ "$LOCAL_ORIGIN" == "$REPO" ]] || die "Origin inesperado: '$LOCAL_ORIGIN'; esperado '$REPO'."
LOCAL_COMMIT="$(git_repo "$CONFIG" rev-parse HEAD)"

# Exporta o histórico local para WORK e consulta o GitHub somente nessa cópia.
# Assim, fetch nunca escreve em /etc/nixos/.git, que pode pertencer ao root.
COMPARE_BUNDLE="$WORK/local-history.bundle"
COMPARE="$WORK/compare"
log "Exportando o histórico local para uma área temporária..."
git_repo "$CONFIG" bundle create "$COMPARE_BUNDLE" --all || \
    die "Não consegui exportar o histórico local para comparação. A configuração ativa não foi modificada."

git clone --no-checkout "$COMPARE_BUNDLE" "$COMPARE" >/dev/null || \
    die "Não consegui preparar a cópia temporária do histórico local."
git -C "$COMPARE" remote set-url origin "$REPO"

log "Buscando a branch remota esperada na cópia temporária..."
git -C "$COMPARE" fetch --no-tags origin "+refs/heads/$BRANCH:refs/remotes/origin/$BRANCH" || \
    die "Falha ao buscar o remoto. Nenhum arquivo de configuração foi substituído."
REMOTE_COMMIT="$(git -C "$COMPARE" rev-parse "refs/remotes/origin/$BRANCH")"

if [[ "$LOCAL_COMMIT" == "$REMOTE_COMMIT" ]]; then
    HAS_UPDATE=0
elif git -C "$COMPARE" merge-base --is-ancestor "$LOCAL_COMMIT" "$REMOTE_COMMIT"; then
    HAS_UPDATE=1
elif git -C "$COMPARE" merge-base --is-ancestor "$REMOTE_COMMIT" "$LOCAL_COMMIT"; then
    die "O commit local ($LOCAL_COMMIT) é mais recente que o remoto ($REMOTE_COMMIT). Não farei downgrade."
else
    die "Históricos local e remoto divergiram. Nenhum reset/merge automático será executado. Resolva a divergência manualmente."
fi

if (( HAS_UPDATE == 0 )) && [[ "$MODE" != "check" ]]; then
    log "Nenhuma atualização remota disponível. O commit local já corresponde ao remoto."
    exit 0
fi

if (( HAS_UPDATE == 1 )); then
    log "Atualização disponível: $LOCAL_COMMIT -> $REMOTE_COMMIT"
    log "Commits remotos a revisar:"
    git -C "$COMPARE" --no-pager log --oneline --decorate "$LOCAL_COMMIT..$REMOTE_COMMIT"
    log "Resumo das alterações rastreadas:"
    git -C "$COMPARE" --no-pager diff --stat "$LOCAL_COMMIT" "$REMOTE_COMMIT"
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
