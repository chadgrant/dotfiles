# mise (preferred) — manages Go, Node, Python, .NET, etc.
if command -v mise >/dev/null 2>&1; then
  eval "$(mise activate zsh)"
fi

# nvm (legacy fallback if mise not used for node)
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"

# bun
export BUN_INSTALL="$HOME/.bun"
[ -d "$BUN_INSTALL/bin" ] && export PATH="$BUN_INSTALL/bin:$PATH"

# dotnet (legacy fallback if mise not used)
export DOTNET_ROOT="$HOME/.dotnet"
[ -d "$DOTNET_ROOT" ] && export PATH="$DOTNET_ROOT:$DOTNET_ROOT/tools:$PATH"

# pnpm global binaries
export PNPM_HOME="$HOME/.local/share/pnpm"
export PATH="$PNPM_HOME:$PATH"
