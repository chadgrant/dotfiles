if [[ -s "${ZDOTDIR:-$HOME}/.zprezto/init.zsh" ]]; then
  source "${ZDOTDIR:-$HOME}/.zprezto/init.zsh"
  if [ "${USEPOWER9k}" = true ]; then
    ZSH_THEME=powerlevel9k
    if prompt -l | grep powerlevel10k > /dev/null 2>&1; then
      ZSH_THEME=powerlevel10k
    fi
    export DEFAULT_USER=$USER
    POWERLEVEL9K_LEFT_PROMPT_ELEMENTS=(context dir vcs)
    POWERLEVEL9K_RIGHT_PROMPT_ELEMENTS=(status root_indicator background_jobs virtualenv time)
    POWERLEVEL9K_PROMPT_ON_NEWLINE=true
  else
    ZSH_THEME=sorin
  fi
  prompt $ZSH_THEME
fi

# Load autosuggestions (shows grayed-out suggestions from history)
[[ -f ~/.zsh/zsh-autosuggestions/zsh-autosuggestions.zsh ]] && source ~/.zsh/zsh-autosuggestions/zsh-autosuggestions.zsh

# Load syntax highlighting (must be loaded last among zsh plugins)
[[ -f ~/.zsh/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh ]] && source ~/.zsh/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh
