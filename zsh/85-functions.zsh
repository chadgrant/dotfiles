whoseport() {
  lsof -i :$1 | grep LISTEN
}

function urlencode() {
  python3 -c 'import urllib.parse,sys; print(urllib.parse.quote(sys.argv[1]))' "$1"
}

cors() {
  curl --head -svH "Origin: http://example.com" -H "Access-Control-Request-Method: GET" $1 2>&1 | grep --color=never Access-Control;
}
