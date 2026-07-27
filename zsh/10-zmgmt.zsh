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
