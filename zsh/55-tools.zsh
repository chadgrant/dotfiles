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

# One ssh-agent: the systemd user agent at ~/.ssh/agent.sock, which ~/.ssh/config
# pins for every ssh and git. Load the key into that agent, once per boot, in the
# first interactive shell. keychain starts an agent of its own, so it held the key
# while every ssh asked the empty pinned agent; it is now only the fallback for a
# machine without the systemd agent.
ssh_agent_socket="$HOME/.ssh/agent.sock"
if [[ -S $ssh_agent_socket ]]; then
  export SSH_AUTH_SOCK=$ssh_agent_socket
  unset SSH_AGENT_PID
  if [[ -o interactive ]] && ! ssh-add -l > /dev/null 2>&1; then
    ssh-add "$HOME/.ssh/id_rsa"
  fi
elif type "keychain" > /dev/null; then
  eval "$(keychain --eval --agents ssh id_rsa)"
fi
unset ssh_agent_socket
