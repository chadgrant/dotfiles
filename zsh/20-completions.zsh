# Setup completions BEFORE zprezto

if [[ ! -d ~/.zsh/completions ]]; then
    mkdir -p ~/.zsh/completions
    command -v docker >/dev/null 2>&1 && docker completion zsh > ~/.zsh/completions/_docker 2>/dev/null
    command -v kubectl >/dev/null 2>&1 && kubectl completion zsh > ~/.zsh/completions/_kubectl 2>/dev/null
    command -v npm >/dev/null 2>&1 && npm completion > ~/.zsh/completions/_npm 2>/dev/null
    command -v xh >/dev/null 2>&1 && xh --generate-completion zsh > ~/.zsh/completions/_xh 2>/dev/null
fi

fpath=(~/.zsh/zsh-completions/src ~/.zsh/completions $fpath)
