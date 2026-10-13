#!/usr/bin/env bash
# Verifies container-init.sh against the homes a container can start with: an
# empty tmpfs, one it already ran in, and a real home bind-mounted from the
# server that has a ~/.zshrc of its own. Needs nothing but bash, so it runs on
# the host as well as in the image:
#
#   bash test/container-init-test.sh
set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
INIT="$REPO/container-init.sh"
WORK="$(mktemp -d)"
trap 'chmod -R u+w "$WORK"; rm -rf "$WORK"' EXIT

pass=0 fail=0

check() {
  local label=$1 got=$2 want=$3
  if [ "$got" = "$want" ]; then
    echo "  PASS  $label"
    pass=$((pass + 1))
  else
    echo "  FAIL  $label"
    echo "          got:  $got"
    echo "          want: $want"
    fail=$((fail + 1))
  fi
}

# Runs the init with HOME at $1; sets rc and err for the checks.
run_init() {
  rc=0
  err="$(HOME="$1" "$INIT" 2>&1 >/dev/null)" || rc=$?
}

echo "== empty home =="

home="$WORK/empty"; mkdir "$home"
run_init "$home"
check "exits 0" "$rc" "0"
check "links ~/.zshrc to the repo's zshrc" "$(readlink "$home/.zshrc")" "$REPO/zshrc"
check "says nothing" "$err" ""

echo "== second start =="

run_init "$home"
check "exits 0" "$rc" "0"
check "link unchanged" "$(readlink "$home/.zshrc")" "$REPO/zshrc"
check "says nothing" "$err" ""

echo "== bind-mounted home with its own ~/.zshrc =="

home="$WORK/real"; mkdir "$home"
echo 'source ~/Documents/chadgrant/dotfiles/zshrc' > "$home/.zshrc"
run_init "$home"
check "exits 0" "$rc" "0"
check "file left as it was" "$(cat "$home/.zshrc")" 'source ~/Documents/chadgrant/dotfiles/zshrc'
check "still a regular file" "$([ -L "$home/.zshrc" ] && echo link || echo file)" "file"
check "says so on stderr" "$(echo "$err" | grep -c 'leaving the existing')" "1"

home="$WORK/foreign-link"; mkdir "$home"
ln -s /somewhere/else/zshrc "$home/.zshrc"
run_init "$home"
check "a dangling link of the user's is left" "$(readlink "$home/.zshrc")" "/somewhere/else/zshrc"
check "and reported" "$(echo "$err" | grep -c 'leaving the existing')" "1"

echo "== home that cannot be written =="

# Root writes through any mode, so the case only exists for other users.
if [ "$(id -u)" -ne 0 ]; then
  home="$WORK/readonly"; mkdir "$home"; chmod 555 "$home"
  run_init "$home"
  check "exits non-zero" "$rc" "1"
  check "explains why" "$(echo "$err" | grep -c '^container-init: ')" "1"
fi

echo
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
