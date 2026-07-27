### GIT ###
# user.name / user.email come from ~/.extra (gitignored) — see .extra.example
if [ ! -f ~/.gitconfig.lock ]; then
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
