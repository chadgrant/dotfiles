unalias ping mkdir ports wget headers envgrep untar mkcd ff 2>/dev/null
alias ping='ping -c 5'
alias mkdir='mkdir -pv'
if [ "${MACOS}" = true ]; then
  alias ports='lsof -iTCP -sTCP:LISTEN -P -n'
else
  alias ports='netstat -tulanp'
fi
alias wget='wget -c'
alias headers='curl -I'
alias envgrep='env | grep'
alias mkcd='_(){ mkdir -pv $1; cd $1; };'
alias ff='find . -name $1'
