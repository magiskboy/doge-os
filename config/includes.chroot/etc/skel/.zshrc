export ZSH="$HOME/.oh-my-zsh"

ZSH_THEME="robbyrussell"

plugins=(
    git
    kubectl
)

source "$ZSH/oh-my-zsh.sh"

export KIND_EXPERIMENTAL_PROVIDER="podman"

alias kind="systemd-run --scope --user --p 'Delegate=true' kind"

export FNM_DIR=/usr/local/share/fnm
eval "$(fnm env --use-on-cd --shell zsh --fnm-dir "$FNM_DIR")"

export UV_PYTHON_INSTALL_DIR=/usr/local/share/uv/python
export UV_TOOL_DIR=/usr/local/share/uv/tools
export UV_TOOL_BIN_DIR=/usr/local/bin

[ -f "$HOME/.cargo/env" ] && . "$HOME/.cargo/env"

export PATH="$PATH:/usr/local/go/bin:$HOME/go/bin"

source /usr/share/zsh-autosuggestions/zsh-autosuggestions.zsh
source /usr/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh
