#!/usr/bin/env zsh
# Verifies the shell loads and that zsh/47-infisical.zsh behaves, using a stub
# Infisical CLI. No credentials, no network, no dependence on a live vault.

ZSHRC=/opt/dotfiles/zshrc
PROJECT=test-project-id
pass=0 fail=0

check() {
  local label=$1 got=$2 want=$3
  if [[ "$got" == "$want" ]]; then
    print "  PASS  $label"
    (( pass++ ))
  else
    print "  FAIL  $label"
    print "          got:  $got"
    print "          want: $want"
    (( fail++ ))
  fi
}

# Each case runs in its own shell so nothing leaks between them.
#
# noclobber is set because prezto and most interactive setups do, and it broke
# the ssh sync once: under it a plain > onto a file we had just created fails,
# which looked exactly like a missing folder. A plain `zsh -c` does not set it,
# so without this the suite tests a shell nobody actually runs.
in_shell() {
  local cache=$1 body=$2
  shift 2
  env "$@" INFISICAL_CACHE="$cache" INFISICAL_PROJECT_ID="$PROJECT" \
    zsh -c "setopt noclobber; source $ZSHRC >/dev/null 2>&1; $body" 2>/dev/null
}

print "== shell loads =="

out=$(zsh -c "source $ZSHRC >/dev/null; print loaded" 2>&1)
check "sources without fatal error" "${out##*$'\n'}" "loaded"

out=$(zsh -c "source $ZSHRC 2>&1 >/dev/null" 2>&1 | grep -icE "parse error|bad pattern|command not found: (secrets|_infisical)")
check "no parse errors or missing functions" "$out" "0"

# gs comes from 80-git.zsh, after the Infisical fragment at 47, and is defined
# unconditionally — so it proves ordering continues past the secrets fetch.
out=$(in_shell /tmp/c-alias 'alias gs')
check "fragments after 47 still apply" "$out" "gs='git status'"

out=$(in_shell /tmp/c-fn 'whence -w secrets-refresh secrets-status secrets-forget | wc -l | tr -d " "')
check "helper commands defined" "$out" "3"

print "== empty project id disables the integration =="

rm -rf /tmp/c-none
out=$(env INFISICAL_CACHE=/tmp/c-none/env INFISICAL_PROJECT_ID= \
  zsh -c "source $ZSHRC >/dev/null 2>&1; print ok" 2>/dev/null)
check "shell still usable" "$out" "ok"
check "nothing fetched" "$([[ -e /tmp/c-none/env ]] && print present || print absent)" "absent"
check "no token in environment" \
  "$(env INFISICAL_CACHE=/tmp/c-none/env INFISICAL_PROJECT_ID= \
     zsh -c "source $ZSHRC >/dev/null 2>&1; print \${GITHUB_TOKEN:-unset}" 2>/dev/null)" "unset"

print "== fetch and cache =="

rm -rf /tmp/c-ok
out=$(in_shell /tmp/c-ok/env 'print "$GITHUB_TOKEN"')
check "GITHUB_TOKEN exported" "$out" "stub-github-token-not-a-real-pat"

check "cache file mode" "$(stat -c %a /tmp/c-ok/env)" "600"
check "cache dir mode" "$(stat -c %a /tmp/c-ok)" "700"

out=$(in_shell /tmp/c-ok2/env 'print "${SSH_PRIVATE_KEY:-unset}"')
check "private key NOT in environment" "$out" "unset"

out=$(in_shell /tmp/c-ok3/env 'print "${SSH_PUBLIC_KEY:-unset}"')
check "public key NOT in environment" "$out" "unset"

check "cache holds no key material" \
  "$(grep -c 'PRIVATE KEY' /tmp/c-ok/env)" "0"

# Values with quotes, $, backticks and backslashes must survive verbatim,
# which is what jq @sh buys over a hand-rolled dotenv.
out=$(in_shell /tmp/c-quote/env 'print -r -- "$TRICKY_VALUE"')
check "hostile value round-trips verbatim" "$out" 'it'"'"'s "quoted" $HOME `backtick` \ end'

out=$(in_shell /tmp/c-count/env 'secrets-status')
check "status counts only exported entries" "${out%% entries*}" "secrets: 3"

print "== refresh, forget =="

rm -rf /tmp/c-cycle
in_shell /tmp/c-cycle/env 'true' >/dev/null
check "cache created" "$([[ -f /tmp/c-cycle/env ]] && print yes || print no)" "yes"

in_shell /tmp/c-cycle/env 'secrets-forget' >/dev/null
check "secrets-forget deletes cache" "$([[ -f /tmp/c-cycle/env ]] && print yes || print no)" "no"

out=$(in_shell /tmp/c-cycle/env 'secrets-forget; secrets-refresh >/dev/null; print "$GITHUB_TOKEN"')
check "secrets-refresh refetches and reloads" "$out" "stub-github-token-not-a-real-pat"

print "== a fresh cache is not refetched =="

# Counts root-path export calls specifically. The session check is a separate
# call, and the ssh folder is fetched with its own export, so neither is what
# "refetch" means here.
exports() { grep -c -- '--path=/ --env=' /tmp/c-calls/log; }

rm -rf /tmp/c-calls; mkdir -p /tmp/c-calls
in_shell /tmp/c-calls/env 'true' STUB_INFISICAL_CALLS=/tmp/c-calls/log >/dev/null
first=$(exports)
in_shell /tmp/c-calls/env 'true' STUB_INFISICAL_CALLS=/tmp/c-calls/log >/dev/null
second=$(exports)
check "second shell makes no new call" "$second" "$first"

# A fresh cache must not even ask whether the session is valid — that is a
# process spawn on the critical path of every interactive shell.
check "fresh cache checks no session" \
  "$(grep -c 'login status' /tmp/c-calls/log)" "1"

# Backdating past the 12h window must trigger exactly one more fetch.
touch -d '20 hours ago' /tmp/c-calls/env
in_shell /tmp/c-calls/env 'true' STUB_INFISICAL_CALLS=/tmp/c-calls/log >/dev/null
third=$(exports)
check "stale cache triggers a refetch" "$(( third - second ))" "1"

print "== server unreachable =="

# A failed fetch must not discard secrets the shell already had.
rm -rf /tmp/c-fallback
in_shell /tmp/c-fallback/env 'true' >/dev/null
touch -d '20 hours ago' /tmp/c-fallback/env
out=$(in_shell /tmp/c-fallback/env 'print "$GITHUB_TOKEN"' STUB_INFISICAL_FAIL=1)
check "stale cache still loads when fetch fails" "$out" "stub-github-token-not-a-real-pat"
check "failed fetch leaves cache intact" \
  "$([[ -s /tmp/c-fallback/env ]] && print yes || print no)" "yes"
check "failed fetch leaves no staged file" \
  "$(ls /tmp/c-fallback | grep -c staged)" "0"

rm -rf /tmp/c-nocache
out=$(env INFISICAL_CACHE=/tmp/c-nocache/env INFISICAL_PROJECT_ID="$PROJECT" STUB_INFISICAL_FAIL=1 \
  zsh -c "source $ZSHRC >/dev/null 2>&1; print still-usable" 2>/dev/null)
check "shell usable with no cache and no server" "$out" "still-usable"

out=$(env INFISICAL_CACHE=/tmp/c-nocache/env INFISICAL_PROJECT_ID="$PROJECT" STUB_INFISICAL_FAIL=1 \
  zsh -c "source $ZSHRC >/dev/null" 2>&1 | grep -c "secrets:")
check "and warns on stderr" "$out" "1"

print "== one environment per machine =="

out=$(in_shell /tmp/c-hostenv/env 'print "$INFISICAL_HOST_ENV"')
check "host env is the short hostname, lowercased" \
  "$out" "$(hostname -s | tr '[:upper:]' '[:lower:]')"

# WHICH_ENV is stamped by the stub with whichever environment it served, so it
# proves which candidate actually won rather than just that something loaded.
rm -rf /tmp/c-envhost
out=$(in_shell /tmp/c-envhost/env 'print "$WHICH_ENV"' \
  INFISICAL_HOST_ENV=allcode STUB_INFISICAL_ENVS="allcode default")
check "machine environment wins over the fallback" "$out" "allcode"

rm -rf /tmp/c-envskip; mkdir -p /tmp/c-envskip
in_shell /tmp/c-envskip/env 'true' INFISICAL_HOST_ENV=allcode \
  STUB_INFISICAL_ENVS="allcode default" STUB_INFISICAL_CALLS=/tmp/c-envskip/log >/dev/null
check "fallback not fetched when the machine has its own" \
  "$(grep -c 'env=default' /tmp/c-envskip/log)" "0"

rm -rf /tmp/c-envfall
out=$(in_shell /tmp/c-envfall/env 'print "$WHICH_ENV"' \
  INFISICAL_HOST_ENV=unknown-box STUB_INFISICAL_ENVS="default")
check "machine with no environment falls back to default" "$out" "default"

check "falling back leaves no staged file" \
  "$(ls /tmp/c-envfall | grep -c staged)" "0"

out=$(in_shell /tmp/c-envfall/env 'secrets-status' \
  INFISICAL_HOST_ENV=unknown-box STUB_INFISICAL_ENVS="default" \
  | grep -c 'environment: default (fallback')
check "status names the environment and why" "$out" "1"

# Neither the machine's environment nor the fallback exists.
rm -rf /tmp/c-envnone
out=$(env INFISICAL_CACHE=/tmp/c-envnone/env INFISICAL_PROJECT_ID="$PROJECT" \
  INFISICAL_HOST_ENV=unknown-box STUB_INFISICAL_ENVS="somewhere-else" \
  zsh -c "source $ZSHRC >/dev/null 2>&1; print ok" 2>/dev/null)
check "shell usable when nothing matches" "$out" "ok"
check "and writes no cache" \
  "$([[ -e /tmp/c-envnone/env ]] && print present || print absent)" "absent"

# Pinning is how a machine deliberately borrows another's secrets.
rm -rf /tmp/c-envpin
out=$(in_shell /tmp/c-envpin/env 'print "$WHICH_ENV"' \
  INFISICAL_ENV=staging INFISICAL_HOST_ENV=allcode \
  STUB_INFISICAL_ENVS="staging allcode default")
check "explicit INFISICAL_ENV pins the environment" "$out" "staging"

rm -rf /tmp/c-envpin2
env INFISICAL_CACHE=/tmp/c-envpin2/env INFISICAL_PROJECT_ID="$PROJECT" \
  INFISICAL_ENV=nonexistent INFISICAL_HOST_ENV=allcode \
  STUB_INFISICAL_ENVS="allcode default" \
  zsh -c "source $ZSHRC >/dev/null 2>&1" >/dev/null 2>&1
check "a pinned environment never falls back" \
  "$([[ -e /tmp/c-envpin2/env ]] && print present || print absent)" "absent"

print "== expired session =="

# The regression this guards: `infisical export` with no session writes an
# interactive picker to stdout, jq chokes on it, and the shell prints
# "jq: parse error: Invalid numeric literal".
rm -rf /tmp/c-expired
in_shell /tmp/c-expired/env 'true' >/dev/null
touch -d '20 hours ago' /tmp/c-expired/env

out=$(env INFISICAL_CACHE=/tmp/c-expired/env INFISICAL_PROJECT_ID="$PROJECT" \
  STUB_INFISICAL_EXPIRED=1 zsh -c "source $ZSHRC >/dev/null" 2>&1 | grep -c "parse error")
check "no jq parse error on expired session" "$out" "0"

out=$(in_shell /tmp/c-expired/env 'print "$GITHUB_TOKEN"' STUB_INFISICAL_EXPIRED=1)
check "cached secrets still load" "$out" "stub-github-token-not-a-real-pat"

check "expired fetch leaves cache intact" \
  "$([[ -s /tmp/c-expired/env ]] && print yes || print no)" "yes"
check "expired fetch leaves no staged file" \
  "$(ls /tmp/c-expired | grep -c staged)" "0"

out=$(env INFISICAL_CACHE=/tmp/c-expired/env INFISICAL_PROJECT_ID="$PROJECT" \
  STUB_INFISICAL_EXPIRED=1 zsh -c "source $ZSHRC >/dev/null" 2>&1 | grep -c "session expired")
check "warns that the session expired" "$out" "1"

# An expired session must never be reported as an unreachable server, since the
# fix for each is different.
out=$(in_shell /tmp/c-expired/env 'secrets-refresh 2>&1 >/dev/null' STUB_INFISICAL_EXPIRED=1 2>&1)
check "secrets-refresh names the real cause" \
  "$(print -r -- "$out" | grep -c 'session expired')" "1"

print "== ssh key files =="

# Last two bytes as hex — proves a trailing newline is present exactly once,
# which ssh-keygen cares about and a naive jq -r would get wrong.
last2() { tail -c2 "$1" | od -An -tx1 | tr -d ' \n' }

SSHD=/tmp/c-sshdir
rm -rf /tmp/c-sshsync "$SSHD"
in_shell /tmp/c-sshsync/env 'true' INFISICAL_SSH_DIR="$SSHD" >/dev/null

check "secret key becomes a file of the same name" \
  "$(ls "$SSHD" 2>/dev/null | sort | tr '\n' ' ')" "config id_rsa id_rsa.pub "

check "private key mode" "$(stat -c %a "$SSHD/id_rsa")" "600"
check "public key mode"  "$(stat -c %a "$SSHD/id_rsa.pub")" "644"
check "config mode"      "$(stat -c %a "$SSHD/config")" "600"
check "ssh dir mode"     "$(stat -c %a "$SSHD")" "700"

# The fixture private key is 4 lines and already newline-terminated, so a
# doubled newline would show as 0a0a and an extra line.
check "multi-line key body intact" "$(wc -l < "$SSHD/id_rsa" | tr -d ' ')" "4"
check "no doubled trailing newline" "$(last2 "$SSHD/id_rsa")" "2d0a"

# The fixture config deliberately has no trailing newline; exactly one is added.
check "missing trailing newline added" "$(last2 "$SSHD/config")" "620a"
check "and only one" "$(wc -l < "$SSHD/config" | tr -d ' ')" "2"

check "sync leaves no staged file" "$(ls -a "$SSHD" | grep -c staged)" "0"
check "sync leaves no fetch temp" "$(ls /tmp/c-sshsync | grep -c ssh-fetch)" "0"

# Overwriting is the point: a stale local file must be replaced, and a loosened
# mode tightened back.
print 'stale' > "$SSHD/id_rsa"
chmod 666 "$SSHD/id_rsa"
rm -f /tmp/c-sshsync/env
in_shell /tmp/c-sshsync/env 'true' INFISICAL_SSH_DIR="$SSHD" >/dev/null
check "existing file is overwritten" "$(wc -l < "$SSHD/id_rsa" | tr -d ' ')" "4"
check "and its mode reset" "$(stat -c %a "$SSHD/id_rsa")" "600"

# Named separately from the in_shell default so the regression is visible: the
# sync reported "no /ssh folder" on every interactive shell until the redirects
# became >|, because > refuses to truncate a file that already exists.
SSHD5=/tmp/c-sshdir-noclobber
rm -rf /tmp/c-sshnc "$SSHD5"
out=$(env INFISICAL_CACHE=/tmp/c-sshnc/env INFISICAL_PROJECT_ID="$PROJECT" \
  INFISICAL_SSH_DIR="$SSHD5" \
  zsh -c "setopt noclobber
          source $ZSHRC >/dev/null 2>&1
          secrets-ssh-sync >/dev/null 2>&1
          print rc=\$?" 2>/dev/null)
check "sync succeeds under noclobber" "$out" "rc=0"
check "and still writes every file" \
  "$(ls "$SSHD5" 2>/dev/null | sort | tr '\n' ' ')" "config id_rsa id_rsa.pub "

print "== ssh file names cannot escape =="

SSHD2=/tmp/c-sshdir-hostile
rm -rf /tmp/c-sshhostile "$SSHD2" /pwned
in_shell /tmp/c-sshhostile/env 'true' INFISICAL_SSH_DIR="$SSHD2" \
  STUB_INFISICAL_SSH_HOSTILE=1 >/dev/null

check "the safe key is still written" \
  "$([[ -f $SSHD2/id_rsa ]] && print yes || print no)" "yes"
check "nothing escaped the ssh directory" \
  "$([[ -e /pwned || -e $SSHD2/nested || -e $SSHD2/.bashrc ]] && print escaped || print contained)" \
  "contained"
check "only the safe name was written" \
  "$(ls "$SSHD2" | sort | tr '\n' ' ')" "id_rsa "

out=$(env INFISICAL_CACHE=/tmp/c-sshhostile2/env INFISICAL_PROJECT_ID="$PROJECT" \
  INFISICAL_SSH_DIR=/tmp/c-sshdir-hostile2 STUB_INFISICAL_SSH_HOSTILE=1 \
  zsh -c "source $ZSHRC >/dev/null" 2>&1 | grep -c "unsafe file name")
check "each unsafe name is refused loudly" "$out" "3"

print "== ssh folder is optional =="

SSHD3=/tmp/c-sshdir-none
rm -rf /tmp/c-sshnone "$SSHD3"
out=$(env INFISICAL_CACHE=/tmp/c-sshnone/env INFISICAL_PROJECT_ID="$PROJECT" \
  INFISICAL_SSH_DIR="$SSHD3" STUB_INFISICAL_NO_SSH_FOLDER=1 \
  zsh -c "source $ZSHRC >/dev/null 2>&1; print ok" 2>/dev/null)
check "a project with no ssh folder still loads" "$out" "ok"
check "and no ssh directory is created" \
  "$([[ -e $SSHD3 ]] && print present || print absent)" "absent"

out=$(env INFISICAL_CACHE=/tmp/c-sshnone2/env INFISICAL_PROJECT_ID="$PROJECT" \
  INFISICAL_SSH_DIR=/tmp/c-sshdir-none2 STUB_INFISICAL_NO_SSH_FOLDER=1 \
  zsh -c "source $ZSHRC >/dev/null" 2>&1 | grep -c "ssh:")
check "and it says nothing at startup" "$out" "0"

# Secrets must never be exported into the environment as a side effect.
out=$(in_shell /tmp/c-sshenv/env 'print "${id_rsa:-unset}/${config:-unset}"' \
  INFISICAL_SSH_DIR=/tmp/c-sshdir-env)
check "ssh secrets do not become variables" "$out" "unset/unset"

print "== secrets-ssh-sync on demand =="

SSHD4=/tmp/c-sshdir-cmd
rm -rf /tmp/c-sshcmd "$SSHD4"
out=$(in_shell /tmp/c-sshcmd/env 'secrets-ssh-sync' INFISICAL_SSH_DIR="$SSHD4")
check "reports what it wrote and at which mode" \
  "$(print -r -- "$out" | grep -c 'id_rsa (600).*id_rsa.pub (644)')" "1"
check "wrote the files" \
  "$(ls "$SSHD4" 2>/dev/null | sort | tr '\n' ' ')" "config id_rsa id_rsa.pub "

out=$(in_shell /tmp/c-sshcmd/env 'secrets-ssh-sync 2>&1 >/dev/null' \
  INFISICAL_SSH_DIR=/tmp/c-sshdir-cmd2 STUB_INFISICAL_NO_SSH_FOLDER=1 2>&1)
check "says so when there is no ssh folder" \
  "$(print -r -- "$out" | grep -c 'no /ssh folder')" "1"

print "== missing dependencies degrade quietly =="

# jq is required to parse the export; without it the fragment must stand down
# rather than half-populate the environment.
rm -rf /tmp/c-nocli
out=$(env PATH=/usr/bin:/bin INFISICAL_CACHE=/tmp/c-nocli/env INFISICAL_PROJECT_ID="$PROJECT" \
  zsh -c "source $ZSHRC >/dev/null 2>&1; print ok" 2>/dev/null)
check "shell loads with infisical off PATH" "$out" "ok"
check "and writes no cache" \
  "$([[ -e /tmp/c-nocli/env ]] && print present || print absent)" "absent"

print ""
print "== $pass passed, $fail failed =="
(( fail == 0 ))
