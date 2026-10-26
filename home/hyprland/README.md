# Hyprland via Home Manager

Este módulo pressupõe que o Hyprland já está habilitado pelo módulo do NixOS (`programs.hyprland.enable = true`). O Home Manager gera `~/.config/hypr/hyprland.lua` e mantém os módulos, scripts, sons, imagem de fundo e configurações auxiliares declarativamente.

## Instalação

1. Extraia a pasta `hyprland` deste pacote dentro de `/etc/nixos/home/`, ficando com `/etc/nixos/home/hyprland/default.nix`.
2. Adicione `./home/hyprland` à lista `imports` do seu `home.nix` (se o `home.nix` estiver na raiz de `/etc/nixos`). Não crie outro `home.nix` se você já tem um.
3. Primeiro valide a configuração atualizada, ainda sem mexer no `~/.config/hypr`:

   ```bash
   sudo nixos-rebuild build --flake /etc/nixos#nixos
   ```

4. Só se o `build` terminar sem erros, faça backup da pasta atual e ative a nova configuração:

   ```bash
   mv ~/.config/hypr ~/.config/hypr.backup-$(date +%F-%H%M%S) && sudo nixos-rebuild switch --flake /etc/nixos#nixos
   ```

Se o `switch` falhar, restaure o backup mais recente antes de sair da sessão. Não apague a pasta de backup até confirmar que tudo funciona. Se o nome da saída no seu `flake.nix` não for `nixos`, troque `#nixos` pelo nome correto.

## O que foi ajustado

- O arquivo `hyprland.lua` não é incluído como fonte: ele é gerado pelo módulo `wayland.windowManager.hyprland`, preservando a ordem de `require()` original.
- `hyprlock` foi removido do autostart. Executá-lo durante a inicialização da sessão pode bloquear a tela imediatamente; ele continua configurado para ser chamado pelo atalho e pelo `hypridle`.
- `songdetail.sh`, chamado pelo `hyprlock.conf` mas ausente no ZIP original, foi adicionado. `playerctl` é instalado por este módulo.
- Os scripts mantêm permissão de execução, e a imagem/sons são instalados nos caminhos usados pelos arquivos existentes.
- Corrigi a limpeza do PID no alternador de `autoclick.sh` e coloquei aspas nos caminhos de saída do script de captura de tela.

## Dependências que continuam externas

- O menu de scripts depende de `~/.config/rofi/utility.rasi`; mantenha esse arquivo gerenciado pelo seu módulo de Rofi.
- As fontes `SF Pro Display Bold`, `AlfaSlabOne` e `JetBrains Mono Nerd` precisam continuar instaladas no sistema ou pelo Home Manager.
- Os comandos chamados pelos scripts (por exemplo `waybar`, `hypridle`, `hyprlock`, `awww-daemon`, `rofi`, `udisksctl`, `cliphist`, `hyprpicker`, `wf-recorder`, `grim`, `slurp`, `wl-copy`, `ydotool`, `pactl`, `paplay`, `brightnessctl`, `playerctl` e `notify-send`) devem estar disponíveis no `PATH`. Somente `playerctl` é instalado por este módulo; os demais não foram movidos de `configuration.nix` para evitar duplicar a gestão de pacotes sem ver a configuração atual.
- Se `programs.hyprland.withUWSM = true` estiver ativo no `configuration.nix`, adicione `systemd.enable = false;` dentro de `wayland.windowManager.hyprland` neste módulo para evitar conflito com UWSM.

## Validação

Os scripts Bash passaram em `bash -n`, e os caminhos referenciados nos arquivos foram revisados. O ambiente de geração não tem Nix nem `luac`, então não foi possível executar aqui `nixos-rebuild build` nem validar a API Lua contra o binário instalado. Faça o `build` descrito acima antes de ativar a configuração.
