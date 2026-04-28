#!/bin/bash

sudo apt-get update
sudo apt-get upgrade -y
sudo apt-get install git curl keychain openssh-server apt-transport-https ca-certificates software-properties-common build-essential unzip jq zsh -y

mkdir ~/.ssh/
chmod 700 ~/.ssh

EXPECTED_HASH="d643d716d3634675fdc037e9434bb6f9cd66eb203b7a0cc8af3399a5112845fe"
curl -fsSL https://raw.githubusercontent.com/chadgrant/dotfiles/main/authorized_keys -o /tmp/ak
echo "$EXPECTED_HASH  /tmp/ak" | sha256sum -c || exit 1
mv /tmp/ak ~/.ssh/authorized_keys

EXPECTED_HASH="b1ba3f7c085369a270d415a33047515763528e42687241a5027c752af7435d33"
curl -fsSL https://raw.githubusercontent.com/chadgrant/dotfiles/main/id_rsa.pub -o /tmp/pubkey
echo "$EXPECTED_HASH  /tmp/pubkey" | sha256sum -c || exit 1
mv /tmp/pubkey ~/.ssh/id_rsa.pub



echo "Paste your private key. Press Ctrl-D when finished:"
umask 077
cat > ~/.ssh/id_rsa

chmod 600 ~/.ssh/authorized_keys
chmod 644 ~/.ssh/*.pub
chmod 600 ~/.ssh/id_rsa
sudo service ssh restart

#configure git
read -rp "Enter your Git email: " GIT_EMAIL

git config --global user.name "Chad Grant"
git config --global user.email "$GIT_EMAIL"
git config --global core.editor "nano"
git config --global url."git@github.com:".insteadOf "https://github.com/"

#configure keychain

echo "eval \`keychain --eval --agents ssh id_rsa\`" >> ~/.bash_profile

#install docker

sudo install -m 0755 -d /etc/apt/keyrings && \
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc && \
sudo chmod a+r /etc/apt/keyrings/docker.asc && \
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null && \
sudo apt-get update && \
sudo apt-get install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin && \
sudo groupadd docker 2> /dev/null || true && \
sudo usermod -aG docker $USER

#install dir env
curl -sfL https://direnv.net/install.sh | bash
sudo echo '#DIRENV HOOK' >> ~/.bashrc
sudo echo 'eval "$(direnv hook bash)"' >> ~/.bashrc

#install kubectl 
VERSION=$(curl -fsSL https://dl.k8s.io/release/stable.txt)
curl -LO "https://dl.k8s.io/release/${VERSION}/bin/linux/amd64/kubectl"
chmod +x kubectl
sudo mv kubectl /usr/local/bin/kubectl

#!/usr/bin/env bash
set -e

# Install Node

# Install nvm (if not already installed)
if [ ! -d "$HOME/.nvm" ]; then
  curl -fsSL https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash
fi

# Load nvm into current shell
export NVM_DIR="$HOME/.nvm"
# shellcheck disable=SC1090
[ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"

# Prompt for Node version
read -rp "Enter Node version (e.g. 20, 18.17.1). Leave empty for latest: " NODE_VERSION

if [ -z "$NODE_VERSION" ]; then
  echo "Installing latest Node..."
  nvm install node
else
  echo "Installing Node version $NODE_VERSION..."
  nvm install "$NODE_VERSION"
fi

# Set default
nvm alias default "$(nvm current)"

# Verify
node -v
npm -v

# Install Bun (latest)
curl -fsSL https://bun.sh/install | bash

# Load bun into PATH for current session
export BUN_INSTALL="$HOME/.bun"
export PATH="$BUN_INSTALL/bin:$PATH"

# Verify
bun --version

#install fzf
FZF_VERSION=$(curl -fsSL https://api.github.com/repos/junegunn/fzf/releases/latest | \
  grep '"tag_name":' | sed -E 's/.*"v([^"]+)".*/\1/')

curl -LO "https://github.com/junegunn/fzf/releases/download/v${FZF_VERSION}/fzf-${FZF_VERSION}-linux_amd64.tar.gz" && \
tar -xvf fzf-*.tar.gz && \
sudo mv fzf /usr/local/bin/fzf && \
rm -f fzf-*.tar.gz

#install fd
FD_VERSION=$(curl -fsSL https://api.github.com/repos/sharkdp/fd/releases/latest | \
  grep '"tag_name":' | sed -E 's/.*"v([^"]+)".*/\1/')

curl -LO "https://github.com/sharkdp/fd/releases/download/v${FD_VERSION}/fd_${FD_VERSION}_amd64.deb" && \
sudo dpkg -i fd_*.deb && \
rm -f fd_*.deb


#setup zsh

zsh 

#do nothing

git clone --recursive https://github.com/sorin-ionescu/prezto.git "${ZDOTDIR:-$HOME}/.zprezto"

#Create a new Zsh configuration by copying the Zsh configuration files provided:

setopt EXTENDED_GLOB
for rcfile in "${ZDOTDIR:-$HOME}"/.zprezto/runcoms/^README.md(.N); do
  ln -s "$rcfile" "${ZDOTDIR:-$HOME}/.${rcfile:t}"
done

#Set Zsh as your default shell:

ZSH_PATH="$(command -v zsh)"

chsh -s "$ZSH_PATH" "$USER"

mkdir -p ~/Documents/chadgrant && ln -s ~/Documents documents

git clone git@github.com:chadgrant/dotfiles.git ~/Documents/chadgrant/dotfiles

echo 'source ~/Documents/chadgrant/dotfiles/zshrc' > ~/.zshrc

source ~/.zshrc