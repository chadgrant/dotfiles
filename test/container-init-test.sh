#!/usr/bin/env bash
# Verifies container-init.sh against the homes a container can start with: an
# empty tmpfs, one it already ran in, and a real home bind-mounted from the
# server that has a ~/.zshrc of its own, both with and without a ZDOTDIR that
# keeps zsh's startup files out of that home. Needs nothing but bash, so it
# runs on the host as well as in the image:
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

# Runs the init with HOME at $1 and, when $2 is given, ZDOTDIR at $2; sets rc
# and err for the checks. ZDOTDIR is cleared otherwise, so the caller's own
# never leaks into a case.
run_init() {
  rc=0
  err="$(env -u ZDOTDIR ${2:+ZDOTDIR="$2"} HOME="$1" "$INIT" 2>&1 >/dev/null)" || rc=$?
}

kind() {
  if [ -L "$1" ]; then echo link; elif [ -e "$1" ]; then echo file; else echo absent; fi
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

echo "== ZDOTDIR set: the home is never read or written =="

home="$WORK/zhome"; mkdir "$home"
zdot="$WORK/zdot/nested"
run_init "$home" "$zdot"
check "exits 0" "$rc" "0"
check "creates ZDOTDIR and links its .zshrc" "$(readlink "$zdot/.zshrc")" "$REPO/zshrc"
check "no ~/.zshrc appears" "$(kind "$home/.zshrc")" "absent"
check "says nothing" "$err" ""

run_init "$home" "$zdot"
check "second start exits 0" "$rc" "0"
check "link unchanged" "$(readlink "$zdot/.zshrc")" "$REPO/zshrc"
check "and says nothing" "$err" ""

home="$WORK/zreal"; mkdir "$home"
echo 'source ~/Documents/chadgrant/dotfiles/zshrc' > "$home/.zshrc"
zdot="$WORK/zreal-zdot"
run_init "$home" "$zdot"
check "a home's own ~/.zshrc does not stop the link" "$(readlink "$zdot/.zshrc")" "$REPO/zshrc"
check "and is left as it was" "$(cat "$home/.zshrc")" 'source ~/Documents/chadgrant/dotfiles/zshrc'
check "without a word" "$err" ""

home="$WORK/zkept"; mkdir "$home"
zdot="$WORK/zkept-zdot"; mkdir "$zdot"
echo '# mine' > "$zdot/.zshrc"
run_init "$home" "$zdot"
check "an existing ZDOTDIR .zshrc exits 0" "$rc" "0"
check "is kept" "$(kind "$zdot/.zshrc")" "file"
check "and reported" "$(echo "$err" | grep -c "leaving the existing $zdot/.zshrc")" "1"

echo "== home that cannot be written =="

# Root writes through any mode, so the case only exists for other users.
if [ "$(id -u)" -ne 0 ]; then
  home="$WORK/readonly"; mkdir "$home"; chmod 555 "$home"
  run_init "$home"
  check "exits non-zero" "$rc" "1"
  check "explains why" "$(echo "$err" | grep -c '^container-init: ')" "1"

  run_init "$WORK/zhome" "$home/zdot"
  check "a ZDOTDIR that cannot be made exits non-zero" "$rc" "1"
  check "and explains why" "$(echo "$err" | grep -c '^container-init: ')" "1"
fi

echo
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
