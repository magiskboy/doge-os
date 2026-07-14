export ZSH="$HOME/.oh-my-zsh"

ZSH_THEME="robbyrussell"

plugins=(
    git
    kubectl
)

source "$ZSH/oh-my-zsh.sh"

export KIND_EXPERIMENTAL_PROVIDER="podman"

alias kind="systemd-run --scope --user --p 'Delegate=true' kind"

eval "$(fnm env --use-on-cd --shell zsh)"

source /usr/share/zsh-autosuggestions/zsh-autosuggestions.zsh
source /usr/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh
