#USER BIN dir
if [[ ! -d ~/bin ]]; then
    mkdir ~/bin
fi

export PATH="$HOME/bin:$PATH"
