# Local, host-specific overrides and secrets — not checked in.
# See .extra.example for what to put here (e.g. git user.email).
[ -f "$HOME/.extra" ] && source "$HOME/.extra"

# Only a terminal has modes to reset. Without one (`zsh -i -c` under docker
# run, ssh with a command) stty fails and says so on stderr.
if [[ -t 0 ]]; then
  stty sane
fi
