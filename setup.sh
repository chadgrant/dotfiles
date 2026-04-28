#!/usr/bin/env bash
set -euo pipefail

TARGET_USER="${SUDO_USER:-$(id -un)}"
TARGET_HOME="$(getent passwd "$TARGET_USER" | cut -d: -f6)"

sudo apt-get update
sudo apt-get upgrade -y

sudo DEBIAN_FRONTEND=noninteractive apt-get install -y apt-utils tzdata
sudo ln -sf /usr/share/zoneinfo/America/Los_Angeles /etc/localtime
sudo dpkg-reconfigure -f noninteractive tzdata

sudo apt-get install git curl keychain openssh-server apt-transport-https ca-certificates software-properties-common build-essential unzip jq zsh -y

printf '\n\nSetting up SSH ...\n\n'

mkdir -p "$TARGET_HOME/.ssh"
chmod 700 "$TARGET_HOME/.ssh"

EXPECTED_HASH="d643d716d3634675fdc037e9434bb6f9cd66eb203b7a0cc8af3399a5112845fe"
curl -fsSL https://raw.githubusercontent.com/chadgrant/dotfiles/refs/heads/master/authorized_keys -o /tmp/ak
echo "$EXPECTED_HASH  /tmp/ak" | sha256sum -c || exit 1
mv /tmp/ak "$TARGET_HOME/.ssh/authorized_keys"

EXPECTED_HASH="b1ba3f7c085369a270d415a33047515763528e42687241a5027c752af7435d33"
curl -fsSL https://raw.githubusercontent.com/chadgrant/dotfiles/refs/heads/master/id_rsa.pub -o /tmp/pubkey
echo "$EXPECTED_HASH  /tmp/pubkey" | sha256sum -c || exit 1
mv /tmp/pubkey "$TARGET_HOME/.ssh/id_rsa.pub"

echo "Paste your private key. End with a blank line."

awk '
  NF == 0 { exit }
  { print }
' | sed 's/\r$//' > /tmp/raw_ssh_key

awk '
  /-----BEGIN OPENSSH PRIVATE KEY-----/ { inkey=1 }
  inkey { print }
  /-----END OPENSSH PRIVATE KEY-----/ { exit }
' /tmp/raw_ssh_key > "$TARGET_HOME/.ssh/id_rsa"

chown -R "$TARGET_USER:$TARGET_USER" "$TARGET_HOME/.ssh"
chmod 600 $TARGET_HOME/.ssh/authorized_keys
chmod 600 $TARGET_HOME/.ssh/id_*
chmod 644 $TARGET_HOME/.ssh/*.pub

sudo service ssh restart

if [ -z "${SSH_AUTH_SOCK:-}" ]; then
  eval "$(ssh-agent -s)"
fi

# Add the target user's key to this agent
if ! ssh-add -l >/dev/null 2>&1; then
  ssh-add "$TARGET_HOME/.ssh/id_rsa"
fi

#configure keychain

echo "eval \`keychain --eval --agents ssh id_rsa\`" >> "$TARGET_HOME/.bash_profile"


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
if [ $(uname) = "Linux" ]; then
  curl -sfL https://github.com/ducaale/xh/releases/download/v${XH_VERSION}/xh-v${XH_VERSION}-$(uname -m)-unknown-linux-musl.tar.gz | sudo -u "$TARGET_USER" tar xz -C "$TARGET_HOME/bin" --strip-components=1
elif [ $(uname) = "Darwin" ]; then
  curl -sfL https://github.com/ducaale/xh/releases/download/v${XH_VERSION}/xh-v${XH_VERSION}-$(uname -m)-apple-darwin.tar.gz | sudo -u "$TARGET_USER" tar xz -C "$TARGET_HOME/bin" --strip-components=1
fi

# Persist ~/bin on PATH for login shells
if ! grep -q 'HOME/bin' /etc/profile; then
  echo 'export PATH="$HOME/bin:$PATH"' | sudo tee -a /etc/profile >/dev/null
fi

# install eza

printf '\n\nInstalling eza ...\n\n'

sudo mkdir -p /etc/apt/keyrings
wget -qO- https://raw.githubusercontent.com/eza-community/eza/main/deb.asc | sudo gpg --dearmor -o /etc/apt/keyrings/gierens.gpg
echo "deb [signed-by=/etc/apt/keyrings/gierens.gpg] http://deb.gierens.de stable main" | sudo tee /etc/apt/sources.list.d/gierens.list
sudo chmod 644 /etc/apt/keyrings/gierens.gpg /etc/apt/sources.list.d/gierens.list
sudo apt update && sudo apt install -y eza


#install docker

printf '\n\nInstalling docker ...\n\n'

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

#install dir env

printf '\n\nInstalling direnv ...\n\n'

curl -sfL https://direnv.net/install.sh | sudo bin_path=/usr/local/bin bash
if ! grep -q 'direnv hook bash' "$TARGET_HOME/.bashrc" 2>/dev/null; then
  sudo -u "$TARGET_USER" tee -a "$TARGET_HOME/.bashrc" >/dev/null <<'EOF'

# direnv hook
eval "$(direnv hook bash)"
EOF
fi

#install kubectl 

printf '\n\nInstalling kubectl ...\n\n'

VERSION=$(curl -fsSL https://dl.k8s.io/release/stable.txt)
curl -fsSLO "https://dl.k8s.io/release/${VERSION}/bin/linux/amd64/kubectl"
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

#install golang

printf '\n\nInstalling golang ...\n\n'

ARCH="linux-amd64"
INSTALL_DIR="/usr/local"

LATEST_VERSION=$(curl -fsSL https://go.dev/dl/?mode=json | jq -r '[.[] | select(.stable==true)][0].version')

echo "Latest Go version is: $LATEST_VERSION"
read -rp "Enter Go version (e.g. go1.22.3). Leave empty for latest: " GO_VERSION

GO_VERSION="${GO_VERSION:-$LATEST_VERSION}"

TARBALL="${GO_VERSION}.${ARCH}.tar.gz"
URL="https://go.dev/dl/${TARBALL}"
echo "Installing $GO_VERSION..."
curl -fsSLO "$URL"
sudo rm -rf "${INSTALL_DIR}/go"
sudo tar -C "$INSTALL_DIR" -xzf "$TARBALL"
rm -f "$TARBALL"
sudo -u "$TARGET_USER" mkdir -p "$TARGET_HOME/go/bin"

if ! grep -q "/usr/local/go/bin" /etc/profile; then
  echo 'export PATH="$PATH:/usr/local/go/bin:$HOME/go/bin"' | sudo tee -a /etc/profile >/dev/null
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

if ! grep -q 'DOTNET_ROOT' /etc/profile; then
  echo 'export DOTNET_ROOT="$HOME/.dotnet"' | sudo tee -a /etc/profile >/dev/null
  echo 'export PATH="$PATH:$DOTNET_ROOT:$DOTNET_ROOT/tools"' | sudo tee -a /etc/profile >/dev/null
fi
export DOTNET_ROOT="$TARGET_HOME/.dotnet"
export PATH="$PATH:$DOTNET_ROOT:$DOTNET_ROOT/tools"

#install fzf

printf '\n\nInstalling fzf ...\n\n'

FZF_VERSION=$(curl -fsSL https://api.github.com/repos/junegunn/fzf/releases/latest | \
  grep '"tag_name":' | sed -E 's/.*"v([^"]+)".*/\1/')

curl -fsSLO "https://github.com/junegunn/fzf/releases/download/v${FZF_VERSION}/fzf-${FZF_VERSION}-linux_amd64.tar.gz" && \
tar -xvf fzf-*.tar.gz && \
sudo mv fzf /usr/local/bin/fzf && \
rm -f fzf-*.tar.gz

#install fd

printf '\n\nInstalling fd ...\n\n'

FD_VERSION=$(curl -fsSL https://api.github.com/repos/sharkdp/fd/releases/latest | \
  grep '"tag_name":' | sed -E 's/.*"v([^"]+)".*/\1/')

curl -fsSLO "https://github.com/sharkdp/fd/releases/download/v${FD_VERSION}/fd_${FD_VERSION}_amd64.deb" && \
sudo dpkg -i fd_*.deb && \
rm -f fd_*.deb

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
sudo chsh -s "$ZSH_PATH" "$TARGET_USER"

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