# Path to your Oh My Zsh installation.
export ZSH="$HOME/.oh-my-zsh"

ZSH_THEME="robbyrussell"

# Disable auto-update prompts in image builds / shared skel copies.
zstyle ':omz:update' mode disabled

plugins=(git)

source "$ZSH/oh-my-zsh.sh"

# fnm — Node version manager (/usr/local/bin/fnm)
eval "$(fnm env --use-on-cd --shell zsh)"

# Debian packages (not OMZ custom plugins)
source /usr/share/zsh-autosuggestions/zsh-autosuggestions.zsh
# syntax-highlighting must load last
source /usr/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh
