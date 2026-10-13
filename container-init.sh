#!/usr/bin/env bash
# Runs at container start, as the session user, before the shell. The other
# half of the contract with `setup.sh --container`, which baked the tools and
# this repo into the image as root but could not know who would run it.
#
# The user is an arbitrary uid, and HOME is either an empty tmpfs or the
# server's real home bind-mounted in. The second case is why this never
# replaces anything it finds: a change here is a change to the user's real
# home on the server. It runs on every start, so it is idempotent, quick, and
# never touches the network.
set -euo pipefail

# The repo's own directory rather than a fixed /opt/dotfiles, so a clone
# anywhere links to itself. zshrc finds its fragments relative to its resolved
# path, so a symlink to it works.
DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
ZSHRC_TARGET="$DOTFILES_DIR/zshrc"
ZSHRC_LINK="$HOME/.zshrc"

zshrc_is_linked() {
  [ -L "$ZSHRC_LINK" ] && [ "$(readlink "$ZSHRC_LINK")" = "$ZSHRC_TARGET" ]
}

if zshrc_is_linked; then
  exit 0
fi

# -L as well as -e: a dangling symlink is still the user's, not a free slot.
if [ -e "$ZSHRC_LINK" ] || [ -L "$ZSHRC_LINK" ]; then
  echo "container-init: leaving the existing $ZSHRC_LINK in place; it is not a link to $ZSHRC_TARGET" >&2
  exit 0
fi

# Two containers sharing a bind-mounted home can race to create the link; the
# loser's ln fails, which is fine as long as the winner made the same link.
if ! ln_error="$(ln -s "$ZSHRC_TARGET" "$ZSHRC_LINK" 2>&1)" && ! zshrc_is_linked; then
  echo "container-init: $ln_error" >&2
  exit 1
fi
