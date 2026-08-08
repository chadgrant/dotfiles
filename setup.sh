#!/usr/bin/env bash
set -euo pipefail

OS="$(uname)"
MACHINE="$(uname -m)"
# normalized arch: amd64 / arm64
case "$MACHINE" in
  x86_64|amd64) ARCH="amd64" ;;
  arm64|aarch64) ARCH="arm64" ;;
  *) ARCH="$MACHINE" ;;
esac

# Self-hosted Infisical instance that supplies this machine's secrets and keys.
# Project "secret-management"; override any of these to bootstrap from elsewhere.
INFISICAL_DOMAIN="${INFISICAL_DOMAIN:-https://infisical.deviantgeek.io}"
INFISICAL_PROJECT_ID="${INFISICAL_PROJECT_ID:-3abbe79b-4cd2-4e68-9e76-4e59d8865f92}"

# The project holds one environment per machine, slugged with that machine's
# short hostname, falling back to "default" — same rule as zsh/47-infisical.zsh,
# which is where it is documented. INFISICAL_ENV is resolved after login, since
# deciding which of the two exists takes an authenticated call.
# `|| true` because set -e would abort the whole script if a machine had no
# hostname command; an empty host env just means the fallback is used.
INFISICAL_HOST_ENV="${INFISICAL_HOST_ENV:-$(hostname -s 2>/dev/null | tr '[:upper:]' '[:lower:]' || true)}"
INFISICAL_ENV_FALLBACK="${INFISICAL_ENV_FALLBACK:-default}"

# Key material sits at the root path alongside everything else. Folder scoping
# was tried and abandoned: `secrets folders create` does not honour --env, so
# the folder was created in dev while prod kept 404ing. What keeps the private
# key out of the shell environment is the name exclusion in
# zsh/47-infisical.zsh, not its location in the project.
INFISICAL_SSH_PATH="/"
SSH_PRIVATE_KEY_SECRET="SSH_PRIVATE_KEY"
SSH_PUBLIC_KEY_SECRET="SSH_PUBLIC_KEY"

TARGET_USER="${SUDO_USER:-$(id -un)}"
if [ "$OS" = "Darwin" ]; then
  TARGET_HOME="$(dscl . -read /Users/"$TARGET_USER" NFSHomeDirectory 2>/dev/null | awk '{print $2}')"
  PROFILE_FILE="/etc/zprofile"
else
  TARGET_HOME="$(getent passwd "$TARGET_USER" | cut -d: -f6)"
  PROFILE_FILE="/etc/profile"
fi
: "${TARGET_HOME:=$HOME}"

as_user() { sudo -u "$TARGET_USER" HOME="$TARGET_HOME" "$@"; }

if [ "$OS" = "Linux" ]; then
  sudo apt-get update
  sudo apt-get upgrade -y

  sudo DEBIAN_FRONTEND=noninteractive apt-get install -y apt-utils tzdata
  sudo ln -sf /usr/share/zoneinfo/America/Los_Angeles /etc/localtime
  sudo dpkg-reconfigure -f noninteractive tzdata

  sudo apt-get install git curl keychain openssh-server apt-transport-https ca-certificates software-properties-common build-essential unzip jq zsh -y
elif [ "$OS" = "Darwin" ]; then
  printf '\n\nEnsuring Xcode Command Line Tools ...\n\n'
  if ! xcode-select -p >/dev/null 2>&1; then
    xcode-select --install || true
    echo "Complete the Xcode CLT install GUI dialog, then re-run this script."
    exit 1
  fi

  printf '\n\nInstalling Homebrew (latest) ...\n\n'
  if ! command -v brew >/dev/null 2>&1; then
    NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  else
    brew update
  fi

  # Make brew available in this shell
  if [ -x /opt/homebrew/bin/brew ]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
  elif [ -x /usr/local/bin/brew ]; then
    eval "$(/usr/local/bin/brew shellenv)"
  fi

  # Minimal brew use: only for tools without easy direct binaries
  brew install jq

  # Set timezone (no tzdata/dpkg-reconfigure on macOS)
  sudo systemsetup -settimezone America/Los_Angeles >/dev/null 2>&1 || true
else
  echo "Unsupported OS: $OS" >&2
  exit 1
fi

#install infisical
#
# Must precede SSH setup: the private key, and every later `git clone` over
# ssh, come out of Infisical.

printf '\n\nInstalling Infisical CLI ...\n\n'

if [ "$OS" = "Linux" ]; then
  curl -1sLf 'https://artifacts-cli.infisical.com/setup.deb.sh' | sudo -E bash
  sudo apt-get update && sudo apt-get install -y infisical
elif [ "$OS" = "Darwin" ]; then
  brew install infisical/get-cli/infisical
fi

# On macOS the login token belongs in the Keychain. Linux and WSL have no
# keyring daemon, so they keep the encrypted file backend.
if [ "$OS" = "Darwin" ]; then
  as_user infisical vault set auto
else
  as_user infisical vault set file
fi

printf '\n\nLogging into Infisical (%s) ...\n' "$INFISICAL_DOMAIN"
printf 'This is the only interactive login; the CLI refreshes itself afterwards.\n\n'

if ! as_user infisical login --domain="$INFISICAL_DOMAIN"; then
  echo "Infisical login did not complete. Run this, then re-run setup.sh:" >&2
  echo "  infisical login --domain=$INFISICAL_DOMAIN" >&2
  exit 1
fi

# An environment that does not exist 404s, so existence is discovered by trying
# it. An explicit INFISICAL_ENV pins the choice and skips both probes.
if [ -z "${INFISICAL_ENV:-}" ]; then
  for candidate in "$INFISICAL_HOST_ENV" "$INFISICAL_ENV_FALLBACK"; do
    [ -n "$candidate" ] || continue
    if as_user infisical export --silent --format=json \
         --domain="$INFISICAL_DOMAIN" \
         --projectId="$INFISICAL_PROJECT_ID" \
         --path="$INFISICAL_SSH_PATH" \
         --env="$candidate" >/dev/null 2>&1; then
      INFISICAL_ENV="$candidate"
      break
    fi
  done
fi

if [ -z "${INFISICAL_ENV:-}" ]; then
  echo "No Infisical environment for this machine ($INFISICAL_HOST_ENV) and no" >&2
  echo "$INFISICAL_ENV_FALLBACK environment to fall back to. Create one, then re-run setup.sh." >&2
  exit 1
fi

printf 'Using Infisical environment: %s\n\n' "$INFISICAL_ENV"

# Writes one key from $INFISICAL_SSH_PATH to a file, creating nothing on
# failure. The file is given its final mode before any key material reaches it.
fetch_ssh_secret_to_file() {
  local secret_name="$1"
  local destination="$2"
  local mode="$3"
  local staged="${destination}.staged.$$"

  install -m "$mode" /dev/null "$staged" || return 1

  # `infisical secrets get --path` 404s against this server while `export`
  # reads the same folder correctly, so the value is pulled out of the JSON
  # export. jq -e fails when the key is absent; -s on the file catches an
  # empty read, since a missing secret must not look like success.
  if ! as_user infisical export --silent --format=json \
        --domain="$INFISICAL_DOMAIN" \
        --projectId="$INFISICAL_PROJECT_ID" \
        --path="$INFISICAL_SSH_PATH" \
        --env="$INFISICAL_ENV" 2>/dev/null \
      | jq -er --arg key "$secret_name" \
          '.[] | select(.key == $key) | .value' > "$staged" \
      || [ ! -s "$staged" ]; then
    rm -f "$staged"
    return 1
  fi

  # ssh-keygen rejects a key whose last line is unterminated. Anything already
  # terminated is left byte-for-byte alone — trailing newlines are part of the
  # original file and stripping them would not reproduce it.
  [ -s "$staged" ] && [ -n "$(tail -c 1 "$staged")" ] && printf '\n' >> "$staged"

  mv -f "$staged" "$destination"
}

printf '\n\nSetting up SSH ...\n\n'

mkdir -p "$TARGET_HOME/.ssh"
chmod 700 "$TARGET_HOME/.ssh"

EXPECTED_HASH="d643d716d3634675fdc037e9434bb6f9cd66eb203b7a0cc8af3399a5112845fe"
curl -fsSL https://raw.githubusercontent.com/chadgrant/dotfiles/refs/heads/master/authorized_keys -o /tmp/ak
echo "$EXPECTED_HASH  /tmp/ak" | sha256sum -c || exit 1
mv /tmp/ak "$TARGET_HOME/.ssh/authorized_keys"

if [ -f "$TARGET_HOME/.ssh/id_rsa" ] && [ -f "$TARGET_HOME/.ssh/id_rsa.pub" ]; then
  echo "SSH key already present at $TARGET_HOME/.ssh/id_rsa, skipping key import."
else
  printf 'Pulling SSH keypair from Infisical ...\n'

  if ! fetch_ssh_secret_to_file "$SSH_PRIVATE_KEY_SECRET" "$TARGET_HOME/.ssh/id_rsa" 600; then
    echo "Could not read $SSH_PRIVATE_KEY_SECRET from Infisical ($INFISICAL_ENV)." >&2
    echo "Upload it first:  infisical secrets set $SSH_PRIVATE_KEY_SECRET=@$TARGET_HOME/.ssh/id_rsa --path=$INFISICAL_SSH_PATH --projectId=$INFISICAL_PROJECT_ID --env=$INFISICAL_ENV" >&2
    exit 1
  fi

  if ! fetch_ssh_secret_to_file "$SSH_PUBLIC_KEY_SECRET" "$TARGET_HOME/.ssh/id_rsa.pub" 644; then
    echo "Could not read $SSH_PUBLIC_KEY_SECRET from Infisical ($INFISICAL_ENV)." >&2
    echo "Upload it first:  infisical secrets set $SSH_PUBLIC_KEY_SECRET=@$TARGET_HOME/.ssh/id_rsa.pub --path=$INFISICAL_SSH_PATH --projectId=$INFISICAL_PROJECT_ID --env=$INFISICAL_ENV" >&2
    exit 1
  fi

  if ! grep -q -- "-----BEGIN .*PRIVATE KEY-----" "$TARGET_HOME/.ssh/id_rsa"; then
    echo "$SSH_PRIVATE_KEY_SECRET does not contain a private key." >&2
    exit 1
  fi

  # -P "" verifies an unencrypted key without ever blocking on a prompt. A
  # passphrase-protected key fails this and that is fine — keychain asks later.
  if ! ssh-keygen -y -P "" -f "$TARGET_HOME/.ssh/id_rsa" >/dev/null 2>&1; then
    echo "Private key is passphrase-protected; keychain will prompt on first use."
  fi
fi

if [ "$OS" = "Darwin" ]; then
  sudo chown -R "$TARGET_USER:staff" "$TARGET_HOME/.ssh"
else
  TARGET_GROUP="$(id -gn "$TARGET_USER")"
  sudo chown -R "$TARGET_USER:$TARGET_GROUP" "$TARGET_HOME/.ssh"
fi
chmod 600 $TARGET_HOME/.ssh/authorized_keys
chmod 600 $TARGET_HOME/.ssh/id_*
chmod 644 $TARGET_HOME/.ssh/*.pub

if [ "$OS" = "Linux" ]; then
  sudo service ssh restart
fi

if [ -z "${SSH_AUTH_SOCK:-}" ]; then
  eval "$(ssh-agent -s)"
fi

# Add the target user's key to this agent
if ! ssh-add -l >/dev/null 2>&1; then
  ssh-add "$TARGET_HOME/.ssh/id_rsa"
fi

#configure keychain (Linux only; macOS uses Apple keychain via ssh-agent)

if [ "$OS" = "Linux" ]; then
  if ! grep -q 'keychain --eval' "$TARGET_HOME/.bash_profile" 2>/dev/null; then
    echo "eval \`keychain --eval --agents ssh id_rsa\`" >> "$TARGET_HOME/.bash_profile"
  fi
elif [ "$OS" = "Darwin" ]; then
  # Use macOS keychain to store passphrase
  ssh-add --apple-use-keychain "$TARGET_HOME/.ssh/id_rsa" 2>/dev/null || true
fi


#configure git

printf '\n\nConfiguring Git ...\n\n'

read -rp "Enter your Git email: " GIT_EMAIL

git config --global user.name "Chad Grant"
git config --global user.email "$GIT_EMAIL"
git config --global core.editor "nano"
#git config --global url."git@github.com:".insteadOf "https://github.com/"


#install xh
printf '\n\nInstalling xh ...\n\n'

sudo -u "$TARGET_USER" mkdir -p "$TARGET_HOME/bin"
XH_VERSION=$(curl -fsSL https://api.github.com/repos/ducaale/xh/releases/latest | \
  grep '"tag_name":' | sed -E 's/.*"v([^"]+)".*/\1/')
if [ "$OS" = "Linux" ]; then
  curl -sfL "https://github.com/ducaale/xh/releases/download/v${XH_VERSION}/xh-v${XH_VERSION}-${MACHINE}-unknown-linux-musl.tar.gz" | sudo -u "$TARGET_USER" tar xz -C "$TARGET_HOME/bin" --strip-components=1
elif [ "$OS" = "Darwin" ]; then
  curl -sfL "https://github.com/ducaale/xh/releases/download/v${XH_VERSION}/xh-v${XH_VERSION}-${MACHINE}-apple-darwin.tar.gz" | sudo -u "$TARGET_USER" tar xz -C "$TARGET_HOME/bin" --strip-components=1
fi

# Persist ~/bin on PATH for login shells
if ! sudo grep -q 'HOME/bin' "$PROFILE_FILE" 2>/dev/null; then
  echo 'export PATH="$HOME/bin:$PATH"' | sudo tee -a "$PROFILE_FILE" >/dev/null
fi

# install eza

printf '\n\nInstalling eza ...\n\n'

if [ "$OS" = "Linux" ]; then
  sudo mkdir -p /etc/apt/keyrings
  wget -qO- https://raw.githubusercontent.com/eza-community/eza/main/deb.asc | sudo gpg --dearmor -o /etc/apt/keyrings/gierens.gpg
  echo "deb [signed-by=/etc/apt/keyrings/gierens.gpg] http://deb.gierens.de stable main" | sudo tee /etc/apt/sources.list.d/gierens.list
  sudo chmod 644 /etc/apt/keyrings/gierens.gpg /etc/apt/sources.list.d/gierens.list
  sudo apt update && sudo apt install -y eza
elif [ "$OS" = "Darwin" ]; then
  EZA_VERSION=$(curl -fsSL https://api.github.com/repos/eza-community/eza/releases/latest | \
    grep '"tag_name":' | sed -E 's/.*"v([^"]+)".*/\1/')
  case "$ARCH" in
    arm64) EZA_TRIPLE="aarch64-apple-darwin" ;;
    amd64) EZA_TRIPLE="x86_64-apple-darwin" ;;
  esac
  TMPDIR_EZA="$(mktemp -d)"
  curl -fsSL -o "$TMPDIR_EZA/eza.zip" "https://github.com/eza-community/eza/releases/download/v${EZA_VERSION}/eza_${EZA_TRIPLE}.zip"
  (cd "$TMPDIR_EZA" && unzip -q eza.zip)
  sudo install -m 0755 "$TMPDIR_EZA/eza" /usr/local/bin/eza
  rm -rf "$TMPDIR_EZA"
fi


#install docker

printf '\n\nInstalling docker ...\n\n'

if [ "$OS" = "Linux" ]; then
  sudo install -m 0755 -d /etc/apt/keyrings && \
  sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc && \
  sudo chmod a+r /etc/apt/keyrings/docker.asc && \
  echo \
    "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
    $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
    sudo tee /etc/apt/sources.list.d/docker.list > /dev/null && \
  sudo apt-get update && \
  sudo apt-get install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin -y

  sudo groupadd -f docker
  sudo usermod -aG docker "$TARGET_USER"
elif [ "$OS" = "Darwin" ]; then
  if [ ! -d "/Applications/Docker.app" ]; then
    echo "Docker Desktop not detected. Install manually from https://www.docker.com/products/docker-desktop/ (or 'brew install --cask docker')."
  fi
fi

#install dir env

printf '\n\nInstalling direnv ...\n\n'

curl -sfL https://direnv.net/install.sh | sudo bin_path=/usr/local/bin bash
BASH_RC_FILE="$TARGET_HOME/.bashrc"
[ "$OS" = "Darwin" ] && BASH_RC_FILE="$TARGET_HOME/.bash_profile"
if ! grep -q 'direnv hook bash' "$BASH_RC_FILE" 2>/dev/null; then
  sudo -u "$TARGET_USER" tee -a "$BASH_RC_FILE" >/dev/null <<'EOF'

# direnv hook
eval "$(direnv hook bash)"
EOF
fi

#install kubectl

printf '\n\nInstalling kubectl ...\n\n'

VERSION=$(curl -fsSL https://dl.k8s.io/release/stable.txt)
KUBE_OS="linux"
[ "$OS" = "Darwin" ] && KUBE_OS="darwin"
curl -fsSLO "https://dl.k8s.io/release/${VERSION}/bin/${KUBE_OS}/${ARCH}/kubectl"
chmod +x kubectl
sudo mv kubectl /usr/local/bin/kubectl

# Install Node

printf '\n\nInstalling node ...\n\n'

read -rp "Enter Node version (e.g. 20, 18.17.1). Leave empty for latest: " NODE_VERSION

# Install nvm + node + bun as the target user so they land in $TARGET_HOME
sudo -u "$TARGET_USER" HOME="$TARGET_HOME" NODE_VERSION="$NODE_VERSION" bash <<'EOF'
set -e
if [ ! -d "$HOME/.nvm" ]; then
  curl -fsSL https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash
fi
export NVM_DIR="$HOME/.nvm"
# shellcheck disable=SC1090
. "$NVM_DIR/nvm.sh"

if [ -z "$NODE_VERSION" ]; then
  echo "Installing latest Node..."
  nvm install node
else
  echo "Installing Node version $NODE_VERSION..."
  nvm install "$NODE_VERSION"
fi
nvm alias default "$(nvm current)"

# Install Bun (latest)
curl -fsSL https://bun.sh/install | bash
export BUN_INSTALL="$HOME/.bun"
export PATH="$BUN_INSTALL/bin:$PATH"

node -v
npm -v
bun --version
EOF

#install claude code

printf '\n\nInstalling Claude Code ...\n\n'

sudo -u "$TARGET_USER" HOME="$TARGET_HOME" bash <<'EOF'
set -e
export NVM_DIR="$HOME/.nvm"
# shellcheck disable=SC1090
. "$NVM_DIR/nvm.sh"
npm install -g @anthropic-ai/claude-code
claude --version || true
EOF

#install Ubuntu Nerd Font

printf '\n\nInstalling Nerd Fonts (Ubuntu + Meslo for Powerlevel10k) ...\n\n'

NF_VERSION=$(curl -fsSL https://api.github.com/repos/ryanoasis/nerd-fonts/releases/latest | \
  grep '"tag_name":' | sed -E 's/.*"v([^"]+)".*/\1/')

# Powerlevel10k recommends MesloLGS NF (Regular/Bold/Italic/Bold Italic)
P10K_FONT_BASE="https://github.com/romkatv/powerlevel10k-media/raw/master"
P10K_FONTS=(
  "MesloLGS%20NF%20Regular.ttf"
  "MesloLGS%20NF%20Bold.ttf"
  "MesloLGS%20NF%20Italic.ttf"
  "MesloLGS%20NF%20Bold%20Italic.ttf"
)

install_fonts_linux() {
  local font_dir="/usr/share/fonts/truetype/nerd-fonts"
  sudo mkdir -p "$font_dir"
  local tmp; tmp="$(mktemp -d)"
  curl -fsSL -o "$tmp/UbuntuMono.zip" \
    "https://github.com/ryanoasis/nerd-fonts/releases/download/v${NF_VERSION}/UbuntuMono.zip"
  curl -fsSL -o "$tmp/Meslo.zip" \
    "https://github.com/ryanoasis/nerd-fonts/releases/download/v${NF_VERSION}/Meslo.zip"
  (cd "$tmp" && unzip -q -o UbuntuMono.zip -d ubuntu && unzip -q -o Meslo.zip -d meslo)
  sudo cp "$tmp"/ubuntu/*.ttf "$font_dir"/ 2>/dev/null || true
  sudo cp "$tmp"/ubuntu/*.otf "$font_dir"/ 2>/dev/null || true
  sudo cp "$tmp"/meslo/*.ttf "$font_dir"/ 2>/dev/null || true
  # Powerlevel10k recommended MesloLGS NF
  for f in "${P10K_FONTS[@]}"; do
    sudo curl -fsSL -o "$font_dir/$(printf '%b' "${f//%/\\x}")" "$P10K_FONT_BASE/$f"
  done
  rm -rf "$tmp"
  command -v fc-cache >/dev/null 2>&1 && sudo fc-cache -f >/dev/null || true
}

install_fonts_mac() {
  sudo -u "$TARGET_USER" HOME="$TARGET_HOME" NF_VERSION="$NF_VERSION" bash <<'EOF'
set -e
FONT_DIR="$HOME/Library/Fonts"
mkdir -p "$FONT_DIR"
TMP="$(mktemp -d)"
curl -fsSL -o "$TMP/UbuntuMono.zip" \
  "https://github.com/ryanoasis/nerd-fonts/releases/download/v${NF_VERSION}/UbuntuMono.zip"
curl -fsSL -o "$TMP/Meslo.zip" \
  "https://github.com/ryanoasis/nerd-fonts/releases/download/v${NF_VERSION}/Meslo.zip"
(cd "$TMP" && unzip -q -o UbuntuMono.zip -d ubuntu && unzip -q -o Meslo.zip -d meslo)
cp "$TMP"/ubuntu/*.ttf "$FONT_DIR"/ 2>/dev/null || true
cp "$TMP"/ubuntu/*.otf "$FONT_DIR"/ 2>/dev/null || true
cp "$TMP"/meslo/*.ttf  "$FONT_DIR"/ 2>/dev/null || true

# Powerlevel10k recommended MesloLGS NF
for f in \
  "MesloLGS%20NF%20Regular.ttf" \
  "MesloLGS%20NF%20Bold.ttf" \
  "MesloLGS%20NF%20Italic.ttf" \
  "MesloLGS%20NF%20Bold%20Italic.ttf"; do
  out="$(printf '%b' "${f//%/\\x}")"
  curl -fsSL -o "$FONT_DIR/$out" "https://github.com/romkatv/powerlevel10k-media/raw/master/$f"
done

rm -rf "$TMP"
EOF
}

if [ "$OS" = "Linux" ]; then
  install_fonts_linux
elif [ "$OS" = "Darwin" ]; then
  install_fonts_mac
fi

#install golang

printf '\n\nInstalling golang ...\n\n'

GO_OS="linux"
[ "$OS" = "Darwin" ] && GO_OS="darwin"
GO_PLATFORM="${GO_OS}-${ARCH}"
INSTALL_DIR="/usr/local"

LATEST_VERSION=$(curl -fsSL https://go.dev/dl/?mode=json | jq -r '[.[] | select(.stable==true)][0].version')

echo "Latest Go version is: $LATEST_VERSION"
read -rp "Enter Go version (e.g. go1.22.3). Leave empty for latest: " GO_VERSION

GO_VERSION="${GO_VERSION:-$LATEST_VERSION}"

TARBALL="${GO_VERSION}.${GO_PLATFORM}.tar.gz"
URL="https://go.dev/dl/${TARBALL}"
echo "Installing $GO_VERSION..."
curl -fsSLO "$URL"
sudo rm -rf "${INSTALL_DIR}/go"
sudo tar -C "$INSTALL_DIR" -xzf "$TARBALL"
rm -f "$TARBALL"
sudo -u "$TARGET_USER" mkdir -p "$TARGET_HOME/go/bin"

if ! sudo grep -q "/usr/local/go/bin" "$PROFILE_FILE" 2>/dev/null; then
  echo 'export PATH="$PATH:/usr/local/go/bin:$HOME/go/bin"' | sudo tee -a "$PROFILE_FILE" >/dev/null
fi
export PATH="$PATH:/usr/local/go/bin:$TARGET_HOME/go/bin"

go version

#install dotnet

printf '\n\nInstalling dotnet ...\n\n'

sudo -u "$TARGET_USER" HOME="$TARGET_HOME" bash <<'EOF'
set -e
curl -fsSL https://dot.net/v1/dotnet-install.sh -o /tmp/dotnet-install.sh
bash /tmp/dotnet-install.sh --channel 10.0
rm -f /tmp/dotnet-install.sh
EOF

if ! sudo grep -q 'DOTNET_ROOT' "$PROFILE_FILE" 2>/dev/null; then
  echo 'export DOTNET_ROOT="$HOME/.dotnet"' | sudo tee -a "$PROFILE_FILE" >/dev/null
  echo 'export PATH="$PATH:$DOTNET_ROOT:$DOTNET_ROOT/tools"' | sudo tee -a "$PROFILE_FILE" >/dev/null
fi
export DOTNET_ROOT="$TARGET_HOME/.dotnet"
export PATH="$PATH:$DOTNET_ROOT:$DOTNET_ROOT/tools"

#install fzf

printf '\n\nInstalling fzf ...\n\n'

FZF_VERSION=$(curl -fsSL https://api.github.com/repos/junegunn/fzf/releases/latest | \
  grep '"tag_name":' | sed -E 's/.*"v([^"]+)".*/\1/')
FZF_OS="linux"
[ "$OS" = "Darwin" ] && FZF_OS="darwin"

curl -fsSLO "https://github.com/junegunn/fzf/releases/download/v${FZF_VERSION}/fzf-${FZF_VERSION}-${FZF_OS}_${ARCH}.tar.gz" && \
tar -xf "fzf-${FZF_VERSION}-${FZF_OS}_${ARCH}.tar.gz" && \
sudo mv fzf /usr/local/bin/fzf && \
rm -f fzf-*.tar.gz

#install fd

printf '\n\nInstalling fd ...\n\n'

FD_VERSION=$(curl -fsSL https://api.github.com/repos/sharkdp/fd/releases/latest | \
  grep '"tag_name":' | sed -E 's/.*"v([^"]+)".*/\1/')

if [ "$OS" = "Linux" ]; then
  FD_DEB_ARCH="amd64"
  [ "$ARCH" = "arm64" ] && FD_DEB_ARCH="arm64"
  curl -fsSLO "https://github.com/sharkdp/fd/releases/download/v${FD_VERSION}/fd_${FD_VERSION}_${FD_DEB_ARCH}.deb" && \
  sudo dpkg -i fd_*.deb && \
  rm -f fd_*.deb
elif [ "$OS" = "Darwin" ]; then
  case "$ARCH" in
    arm64) FD_TRIPLE="aarch64-apple-darwin" ;;
    amd64) FD_TRIPLE="x86_64-apple-darwin" ;;
  esac
  FD_TARBALL="fd-v${FD_VERSION}-${FD_TRIPLE}.tar.gz"
  curl -fsSLO "https://github.com/sharkdp/fd/releases/download/v${FD_VERSION}/${FD_TARBALL}"
  tar -xzf "$FD_TARBALL"
  sudo install -m 0755 "fd-v${FD_VERSION}-${FD_TRIPLE}/fd" /usr/local/bin/fd
  rm -rf "$FD_TARBALL" "fd-v${FD_VERSION}-${FD_TRIPLE}"
fi

#setup zsh

printf '\n\nConfiguring zsh ...\n\n'

ZDOTDIR="${ZDOTDIR:-$TARGET_HOME}"

# Install prezto if missing
if [ ! -d "$ZDOTDIR/.zprezto" ]; then
  sudo -u "$TARGET_USER" \
    GIT_CONFIG_NOSYSTEM=1 \
    GIT_CONFIG_GLOBAL=/dev/null \
    git clone --recursive https://github.com/sorin-ionescu/prezto.git "$ZDOTDIR/.zprezto"
fi

# Create Prezto symlinks as target user
sudo -u "$TARGET_USER" ZDOTDIR="$ZDOTDIR" zsh -c '
  setopt EXTENDED_GLOB
  for rcfile in "$ZDOTDIR"/.zprezto/runcoms/^README.md(.N); do
    target="$ZDOTDIR/.${rcfile:t}"
    [ -e "$target" ] || ln -s "$rcfile" "$target"
  done
'

# Set login shell
ZSH_PATH="$(command -v zsh)"
grep -qxF "$ZSH_PATH" /etc/shells || echo "$ZSH_PATH" | sudo tee -a /etc/shells >/dev/null
if getent passwd "$TARGET_USER" >/dev/null 2>&1 && grep -q "^$TARGET_USER:" /etc/passwd 2>/dev/null; then
  sudo chsh -s "$ZSH_PATH" "$TARGET_USER"
else
  echo "Skipping chsh: '$TARGET_USER' is not a local /etc/passwd user (likely LDAP/SSSD/AD)."
  echo "Set your login shell via your directory service, or run: sudo usermod -s $ZSH_PATH $TARGET_USER"
fi

# Dotfiles
sudo -u "$TARGET_USER" mkdir -p "$TARGET_HOME/Documents/chadgrant"

if [ ! -e "$TARGET_HOME/documents" ]; then
  sudo -u "$TARGET_USER" ln -s "$TARGET_HOME/Documents" "$TARGET_HOME/documents"
fi

if [ ! -d "$TARGET_HOME/Documents/chadgrant/dotfiles" ]; then
  sudo -u "$TARGET_USER" \
  HOME="$TARGET_HOME" \
  SSH_AUTH_SOCK="$SSH_AUTH_SOCK" \
  GIT_SSH_COMMAND="ssh -o StrictHostKeyChecking=accept-new" \
  git clone git@github.com:chadgrant/dotfiles.git \
  "$TARGET_HOME/Documents/chadgrant/dotfiles"
fi

sudo -u "$TARGET_USER" tee "$TARGET_HOME/.zshrc" >/dev/null <<'EOF'
source ~/Documents/chadgrant/dotfiles/zshrc
EOF

printf '\n\nInstalling zsh completions ...\n\n'

# zsh completions (run as target user so files land in $TARGET_HOME with correct ownership)
sudo -u "$TARGET_USER" HOME="$TARGET_HOME" bash <<'EOF'
set -e
mkdir -p "$HOME/.zsh/completions"
[ -d "$HOME/.zsh/zsh-completions" ]        || git clone https://github.com/zsh-users/zsh-completions.git "$HOME/.zsh/zsh-completions"
[ -d "$HOME/.zsh/zsh-autosuggestions" ]    || git clone https://github.com/zsh-users/zsh-autosuggestions.git "$HOME/.zsh/zsh-autosuggestions"
[ -d "$HOME/.zsh/zsh-syntax-highlighting" ]|| git clone https://github.com/zsh-users/zsh-syntax-highlighting.git "$HOME/.zsh/zsh-syntax-highlighting"
EOF
