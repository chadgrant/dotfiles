setopt HIST_IGNORE_SPACE

USERNAME=$USER

LINUX=false
if [ $(uname) = "Linux" ]; then
  LINUX=true
fi

ITERM=false
if [[ ${TERM_PROGRAM} =~ .*iTerm* ]]; then
  ITERM=true
fi

VSCODE=false
if [[ ${TERM_PROGRAM} =~ .*vscode* ]]; then
  VSCODE=true
fi

WSL=false
if [ "${WSL_DISTRO_NAME}x" != "x" ]; then
  if [ "${WSL_USER}x" != "x" ]; then
    USERNAME=$WSL_USER
  fi
  WSL=true
fi

USEPOWER9k=false

if [[ "${ITERM}" = true || "${LINUX}" = true ]]; then
  USEPOWER9k=true

  if [ "${WSL}" = true ]; then
    USEPOWER9k=true
  fi

  if [ "${VSCODE}" = true ]; then
    USEPOWER9k=false
  fi

fi

EDITOR=nano
ZSHRC_DIR=~/Documents/chadgrant/dotfiles
ZSHRC_FILE=$ZSHRC_DIR/zshrc

function zget() {
  if [[ ! -a $ZSHRC_DIR ]]; then
    git clone git@github.com:chadgrant/dotfiles.git $ZSHRC_DIR
  fi

  cd $ZSHRC_DIR
  git pull
  cd -
  zreload
}

function zupdate() {
  cd $ZSHRC_DIR
  git add -A
  git commit -m "update zshrc"
  git push origin master
  cd -
  zreload
}

function zedit() {
  if type "code" > /dev/null; then
    code $ZSHRC_FILE
  else
    eval $EDITOR $ZSHRC_FILE
  fi
}

function zreload() {
  source $ZSHRC_FILE
}

function killvpn() {
  sudo pkill -f openvpn
}

# Setup completions BEFORE zprezto
if [[ ! -d ~/.zsh/zsh-completions ]]; then
    git clone https://github.com/zsh-users/zsh-completions.git ~/.zsh/zsh-completions
fi

if [[ ! -d ~/.zsh/completions ]]; then
    mkdir -p ~/.zsh/completions
    command -v docker >/dev/null 2>&1 && docker completion zsh > ~/.zsh/completions/_docker 2>/dev/null
    command -v kubectl >/dev/null 2>&1 && kubectl completion zsh > ~/.zsh/completions/_kubectl 2>/dev/null
    command -v npm >/dev/null 2>&1 && npm completion > ~/.zsh/completions/_npm 2>/dev/null
    command -v xh >/dev/null 2>&1 && xh --generate-completion zsh > ~/.zsh/completions/_xh 2>/dev/null
fi

if [[ ! -f ~/.zsh/completions/_jq ]]; then
  curl -sfL https://raw.githubusercontent.com/jqlang/jq/master/jq.zsh -o ~/.zsh/completions/_jq
fi

# Install zsh-autosuggestions for history-based suggestions
if [[ ! -d ~/.zsh/zsh-autosuggestions ]]; then
    git clone https://github.com/zsh-users/zsh-autosuggestions.git ~/.zsh/zsh-autosuggestions
fi

# Install zsh-syntax-highlighting for command validation
if [[ ! -d ~/.zsh/zsh-syntax-highlighting ]]; then
    git clone https://github.com/zsh-users/zsh-syntax-highlighting.git ~/.zsh/zsh-syntax-highlighting
fi

fpath=(~/.zsh/zsh-completions/src ~/.zsh/completions $fpath)

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
    #  if [[ ! -a ~/.zsh/git-prompt ]]; then
    #    git clone git://github.com/olivierverdier/zsh-git-prompt.git ~/.zsh/git-prompt
    #  fi

    #  source ~/.zsh/git-prompt/zshrc.sh
    #  PROMPT='%B%m%~%b$(git_super_status) %# '
  fi
  prompt $ZSH_THEME
fi

# Load autosuggestions (shows grayed-out suggestions from history)
[[ -f ~/.zsh/zsh-autosuggestions/zsh-autosuggestions.zsh ]] && source ~/.zsh/zsh-autosuggestions/zsh-autosuggestions.zsh

# Load syntax highlighting (must be loaded last)
[[ -f ~/.zsh/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh ]] && source ~/.zsh/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh


#USER BIN dir
if [[ ! -d ~/bin ]]; then
    mkdir ~/bin
fi

export PATH="$HOME/bin:$PATH"

if ! type "direnv" > /dev/null; then
  echo "installing direnv"
  sudo curl -sfL https://direnv.net/install.sh | bash > /dev/null 2>&1
fi
eval "$(direnv hook zsh)"

#bat
if type "batcat" > /dev/null; then
  alias cat='batcat'
  alias bat='batcat'
  alias catcat='/usr/bin/cat'
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

  # Use fd (https://github.com/sharkdp/fd) for listing path candidates.
  # - The first argument to the function ($1) is the base path to start traversal
  # - See the source code (completion.{bash,zsh}) for the details.
  _fzf_compgen_path() {
    fd --hidden --exclude .git . "$1"
  }

  # Use fd to generate the list for directory completion
  _fzf_compgen_dir() {
    fd --type=d --hidden --exclude .git . "$1"
  }
fi

if [ "${LINUX}" = true ]; then
  if ! type "eza" > /dev/null; then
      echo "installing eza"
      sudo mkdir -p /etc/apt/keyrings
      wget -qO- https://raw.githubusercontent.com/eza-community/eza/main/deb.asc | sudo gpg --dearmor -o /etc/apt/keyrings/gierens.gpg
      echo "deb [signed-by=/etc/apt/keyrings/gierens.gpg] http://deb.gierens.de stable main" | sudo tee /etc/apt/sources.list.d/gierens.list
      sudo chmod 644 /etc/apt/keyrings/gierens.gpg /etc/apt/sources.list.d/gierens.list
      sudo apt update
      sudo apt install -y eza
  else
    unalias la ll ls tree 2>/dev/null
    alias ls='eza --git'
    alias la='eza -lah --grid --git'
    alias ll='eza -lah --grid --git'
    alias tree='eza -T --git'
  fi
fi

if type "keychain" > /dev/null; then
  eval `keychain --eval --agents ssh id_rsa cgrant`
fi

whoseport() {
  lsof -i :$1 | grep LISTEN
}

#GOLANG
if [ -f /usr/local/go/bin/go ]; then
  export GOPROXY=https://goproxy.shrinkled.com,direct
  export PATH=$PATH:/usr/local/go/bin
  export PATH=$PATH:$HOME/go/bin
fi

unalias gt 2>/dev/null
alias gt='go test -v ./...'


#xh - modern curl alternative
if ! type "xh" > /dev/null; then
  echo "installing xh"
  XH_VERSION=0.25.0
  if [ $(uname) = "Linux" ]; then
    curl -sfL https://github.com/ducaale/xh/releases/download/v${XH_VERSION}/xh-v${XH_VERSION}-$(uname -m)-unknown-linux-musl.tar.gz | tar xz -C $HOME/bin --strip-components=1
  elif [ $(uname) = "Darwin" ]; then
    curl -sfL https://github.com/ducaale/xh/releases/download/v${XH_VERSION}/xh-v${XH_VERSION}-$(uname -m)-apple-darwin.tar.gz | tar xz -C $HOME/bin --strip-components=1
  fi
fi


#NODE
# NODE_VERSION=18.16.0
# NODE_DISTRO=x64

# if [ -f /usr/local/lib/nodejs/node-v$NODE_VERSION-linux-$NODE_DISTRO/bin/node ]; then
#   export PATH=/usr/local/lib/nodejs/node-v$NODE_VERSION-linux-$NODE_DISTRO/bin:$PATH
# fi

# pnpm global binaries
export PNPM_HOME="$HOME/.local/share/pnpm"
export PATH="$PNPM_HOME:$PATH"
export DOCKER_DEFAULT_PLATFORM=linux/amd64

function docker_stop_containers() {
  docker_start
  if [[ $(docker ps -q) ]]; then
    echo "[docker]: stopping containers ..."
    docker stop $(docker ps -q)
  fi
}

function docker_remove_containers() {
  docker_start
  if [[ $(docker ps -qf status=exited) ]]; then
    echo "[docker]: removing containers ..."
    docker rm $(docker ps -qf status=exited)
  fi
  if [[ $(docker ps -qf status=created) ]]; then
    echo "[docker]: removing containers ..."
    docker rm $(docker ps -qf status=created)
  fi
}

function docker_remove_dangling_images() {
  docker_start
  if [[ $(docker images -qf dangling=true) ]]; then
    echo "[docker]: removing dangling images ..."
    docker rmi $(docker images -qf dangling=true)
  fi
}

function docker_remove_dangling_volumes() {
  docker_start
  if [[ $(docker volume ls -qf dangling=true) ]]; then
    echo "[docker]: removing dangling volumes ..."
    docker volume rm $(docker volume ls -qf dangling=true)
  fi
}

function docker_remove_dangling_networks() {
  docker_start
  if [[ $(docker network ls -qf dangling=true) ]]; then
    echo "[docker]: removing dangling networks ..."
    docker network rm $(docker network ls -qf dangling=true)
  fi
}

function docker_remove_images() {
  docker_start
  if [[ $(docker images --format '{{.Repository}}:{{.Tag}}' | grep "$1") ]]; then
    docker rmi -f $(docker images --format '{{.Repository}}:{{.Tag}}' | grep "$1")
  fi
}

function docker_clean() {
  docker_start
  docker_stop_containers
  docker_remove_containers
  docker_remove_dangling_images
  docker_remove_dangling_volumes
  docker_remove_dangling_networks
}

function docker_images() {
  docker_start
  docker images
}

function docker_start() {
  if [ $(uname) = "Linux" ] ; then return 0; fi

  if [ "${WSL_DISTRO_NAME}x" = "x" ]; then
    setopt +o nomatch
    running=$(ps -ax | grep [c]om.docker.hyperkit)
    running="${running#"${running%%[![:space:]]*}"}"
    if [[ ${#running} == 0 ]]; then
      echo "starting docker..."
      open /Applications/Docker.app && sleep 20
    fi
    setopt nomatch
  fi
}

unalias drm drmi drmu drmv drmn ds dc di vpn compose 2>/dev/null
alias drm='docker_remove_containers'
alias drmi='docker_remove_images'
alias drmu='docker_remove_dangling_images'
alias drmv='docker_remove_dangling_volumes'
alias drmn='docker_remove_dangling_networks'
alias ds='docker_stop_containers'
alias dc='docker_clean'
alias di='docker_images'
alias d='docker'
alias k='kubectl'

function compose() {
  docker_start
  docker-compose
}

function urlencode() {
  python3 -c 'import urllib.parse,sys; print(urllib.parse.quote(sys.argv[1]))' "$1"
}

 
### Dotnet

export DOTNET_ROOT=$HOME/.dotnet
export PATH=$PATH:$DOTNET_ROOT:$DOTNET_ROOT/tools

if ! type "dotnet" > /dev/null; then
  echo "dotnet not installed"
  curl -L https://dot.net/v1/dotnet-install.sh -o dotnet-install.sh
  bash dotnet-install.sh --channel 10.0
  rm -f dotnet-install.sh
fi

# zsh parameter completion for the dotnet CLI
_dotnet_zsh_complete()
{
  local completions=("$(dotnet complete "$words")")

  if [ -z "$completions" ]
  then
    _arguments '*::arguments: _normal'
    return
  fi

  _values = "${(ps:\n:)completions}"
}

compdef _dotnet_zsh_complete dotnet

### GIT ###
if [ ! -f ~/.gitconfig.lock ]; then
  git config --global user.name "Chad Grant"
  git config --global user.email chad.grant@me.com
  git config --global url.ssh://git@github.com/.insteadof https://github.com/
  git config --global core.editor "code --new-window --wait"
  git config --global core.difftool 'code --new-window --wait --diff $LOCAL $REMOTE'
fi

unalias pull gs ga 2>/dev/null
alias pull='git pull'
alias gs='git status'
alias ga='git add -A'
alias g='git'

push() {
  branch=$(git rev-parse --abbrev-ref HEAD)
  git push origin "$branch" --tags
}

commit() {
  git commit -m "$*"
}

gac() {
  ga
  git commit -a -m "$*"
}

gacp() {
  ga
  git commit -m "$*"
  push
}

gitdeleteremotetag() {
  git tag --delete $1 && git push --delete origin $1
}

### misc ###

unalias ping mkdir ports wget headers envgrep untar mkcd ff 2>/dev/null
alias ping='ping -c 5'
alias mkdir='mkdir -pv'
alias ports='netstat -tulanp'
alias wget='wget -c'
alias headers='curl -I'
alias envgrep='env | grep'
alias mkcd='_(){ mkdir -pv $1; cd $1; };'
alias ff='find . -name $1'

cors() {
  curl --head -svH "Origin: http://example.com" -H "Access-Control-Request-Method: GET" $1 2>&1 | grep --color=never Access-Control;
}

### Documents ###

export DOC_ROOT=~/Documents

if [ "${WSL_DISTRO_NAME}x" != "x" ]; then
  if [ -d /c/Users/${USERNAME}/Documents/github ] ; then
    export DOC_ROOT=/c/Users/${USERNAME}/Documents/github
  fi
fi

unalias documents chadgrant icanotes 2>/dev/null
alias documents='cd $DOC_ROOT'

alias chadgrant='cd $DOC_ROOT/chadgrant'
for d in $DOC_ROOT/chadgrant/*
do
  dir=$(basename $d)
  if [ -d "${d}" ]; then
    unalias $dir 2>/dev/null
    alias $dir="cd $DOC_ROOT/chadgrant/$dir"
  fi
done

alias icanotes='cd $DOC_ROOT/icanotes'
for d in $DOC_ROOT/icanotes/*
do
  dir=$(basename $d)
  if [ -d "${d}" ]; then
    unalias $dir 2>/dev/null
    alias $dir="cd $DOC_ROOT/icanotes/$dir"
  fi
done

unalias goproxy 2>/dev/null

stty sane