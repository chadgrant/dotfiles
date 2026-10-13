#!/usr/bin/env bash
# Starts a shell the way a Remote AI Docker session does, inside the image
# test/container.Dockerfile builds: container-init.sh as the session user,
# then an interactive zsh. Run it as an arbitrary uid with HOME on an empty
# tmpfs, which is what a session gets:
#
#   docker run --rm --user 1000:1000 -e HOME=/home/u \
#     --tmpfs /home/u:mode=1777 dotfiles-container-test
#
# Add -e ZDOTDIR=/home/u/.zdot for a session whose HOME is the server's own:
# zsh must then start from ZDOTDIR and ~/.zshrc must never be written.
#
# Passes when zsh loads the dotfiles (the gs alias from 80-git), finds the
# tools, and nothing at all was written to stderr: a warning at shell start
# lands in front of every session. The last line of output on success is the
# shell's own "zsh direnv infisical jq ok".
set -uo pipefail

stderr_log="$(mktemp)"
trap 'rm -f "$stderr_log"' EXIT

/opt/dotfiles/container-init.sh 2>>"$stderr_log" \
  && zsh -i -c 'alias gs >/dev/null && command -v direnv infisical jq >/dev/null && echo zsh direnv infisical jq ok' 2>>"$stderr_log"
rc=$?

if [ -n "${ZDOTDIR:-}" ] && { [ -e "$HOME/.zshrc" ] || [ -L "$HOME/.zshrc" ]; }; then
  echo "FAIL: ZDOTDIR is set, yet $HOME/.zshrc was written" >&2
  exit 1
fi

if [ -s "$stderr_log" ]; then
  echo "FAIL: shell start wrote to stderr:" >&2
  cat "$stderr_log" >&2
  exit 1
fi
exit "$rc"
