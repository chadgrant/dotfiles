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
in_shell() {
  local cache=$1 body=$2
  shift 2
  env "$@" INFISICAL_CACHE="$cache" INFISICAL_PROJECT_ID="$PROJECT" \
    zsh -c "source $ZSHRC >/dev/null 2>&1; $body" 2>/dev/null
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
check "status counts only exported entries" "${out%% entries*}" "secrets: 2"

print "== refresh, forget =="

rm -rf /tmp/c-cycle
in_shell /tmp/c-cycle/env 'true' >/dev/null
check "cache created" "$([[ -f /tmp/c-cycle/env ]] && print yes || print no)" "yes"

in_shell /tmp/c-cycle/env 'secrets-forget' >/dev/null
check "secrets-forget deletes cache" "$([[ -f /tmp/c-cycle/env ]] && print yes || print no)" "no"

out=$(in_shell /tmp/c-cycle/env 'secrets-forget; secrets-refresh >/dev/null; print "$GITHUB_TOKEN"')
check "secrets-refresh refetches and reloads" "$out" "stub-github-token-not-a-real-pat"

print "== a fresh cache is not refetched =="

rm -rf /tmp/c-calls; mkdir -p /tmp/c-calls
in_shell /tmp/c-calls/env 'true' STUB_INFISICAL_CALLS=/tmp/c-calls/log >/dev/null
first=$(wc -l < /tmp/c-calls/log | tr -d ' ')
in_shell /tmp/c-calls/env 'true' STUB_INFISICAL_CALLS=/tmp/c-calls/log >/dev/null
second=$(wc -l < /tmp/c-calls/log | tr -d ' ')
check "second shell makes no new call" "$second" "$first"

# Backdating past the 12h window must trigger exactly one more fetch.
touch -d '20 hours ago' /tmp/c-calls/env
in_shell /tmp/c-calls/env 'true' STUB_INFISICAL_CALLS=/tmp/c-calls/log >/dev/null
third=$(wc -l < /tmp/c-calls/log | tr -d ' ')
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
