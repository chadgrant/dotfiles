#bat (Linux ships as `batcat`, macOS as `bat`)
if type "batcat" > /dev/null 2>&1; then
  alias cat='batcat'
  alias bat='batcat'
  alias catcat='/bin/cat'
elif type "bat" > /dev/null 2>&1; then
  alias cat='bat'
  alias catcat='/bin/cat'
fi

#fzf
if ! type "fzf" > /dev/null; then
  echo "fzf missing"
else
  eval "$(fzf --zsh)"
fi

#fd
if ! type "fd" > /dev/null; then
  echo "fd not installed"
else
  export FZF_DEFAULT_COMMAND="fd --hidden --strip-cwd-prefix --exclude .git"
  export FZF_CTRL_T_COMMAND="$FZF_DEFAULT_COMMAND"
  export FZF_ALT_C_COMMAND="fd --type=d --hidden --strip-cwd-prefix --exclude .git"

  _fzf_compgen_path() {
    fd --hidden --exclude .git . "$1"
  }

  _fzf_compgen_dir() {
    fd --type=d --hidden --exclude .git . "$1"
  }
fi

if type "eza" > /dev/null 2>&1; then
  unalias la ll ls tree 2>/dev/null
  alias ls='eza --git'
  alias la='eza -lah --grid --git'
  alias ll='eza -lah --grid --git'
  alias tree='eza -T --git'
fi

if type "keychain" > /dev/null; then
  eval `keychain --eval --agents ssh id_rsa`
fi
