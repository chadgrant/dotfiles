#GOLANG
if [ -f /usr/local/go/bin/go ]; then
  export GOPROXY=https://goproxy.shrinkled.com,direct
  export PATH=$PATH:/usr/local/go/bin
  export PATH=$PATH:$HOME/go/bin

  unalias gt 2>/dev/null
  alias gt='go test -v ./...'
elif command -v go >/dev/null 2>&1; then
  # mise-managed go
  export GOPROXY=https://goproxy.shrinkled.com,direct
  export PATH=$PATH:$HOME/go/bin
  unalias gt 2>/dev/null
  alias gt='go test -v ./...'
fi
