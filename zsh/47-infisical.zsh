# Secrets come from Infisical, never from this repo.
# The export is cached on disk so opening a shell costs no network round-trip.
#
#   secrets-refresh    re-fetch now and reload into this shell
#   secrets-status     which environment, how old, and whether the session is live
#   secrets-ssh-sync   rewrite ~/.ssh from the project's ssh folder
#   secrets-forget     delete the cache
#
# Two kinds of secret, kept apart by where they live in the project. Secrets at
# the root path become environment variables. Secrets in the ssh folder become
# files in ~/.ssh, one per secret, named by the secret's key: "id_rsa.pub"
# becomes ~/.ssh/id_rsa.pub. Public keys are written 644 and everything else
# 600. ~/.ssh is rewritten whenever the cache is refetched, so local edits to
# files that are also in the project do not survive.
#
# The project holds one environment per machine, slugged with that machine's
# short hostname. A machine with no environment of its own gets "default", so a
# new box works before it has been given any secrets of its own. Export
# INFISICAL_ENV before the shell starts to pin one environment and skip both
# steps.
#
# Anything in ~/.extra is sourced later and therefore wins over these values.
#
# INFISICAL_DOMAIN only takes effect at `infisical login` time (see setup.sh).
# Once logged in the CLI uses the domain it recorded and ignores both --domain
# and INFISICAL_API_URL, so `secrets-status` reports the recorded one.

: ${INFISICAL_DOMAIN:=https://infisical.deviantgeek.io}

# Assigned only when unset, so exporting an empty INFISICAL_PROJECT_ID before
# the shell starts turns Infisical off for that machine. Using := here would
# substitute the default over the empty value and re-enable it.
: ${INFISICAL_PROJECT_ID=3abbe79b-4cd2-4e68-9e76-4e59d8865f92}
: ${INFISICAL_CACHE:=$HOME/.cache/infisical/env}
: ${INFISICAL_CACHE_MAX_AGE_HOURS:=12}

# The project keeps one environment per machine, named for that machine. The
# short hostname is lowercased because Infisical slugs environments that way,
# and the domain is stripped so a Mac reporting "Foo-MacBook-Pro.local" and the
# same box on a different network both resolve to "foo-macbook-pro".
: ${INFISICAL_HOST_ENV:=${${HOST%%.*}:l}}

# A machine with no environment of its own falls back to this one rather than
# starting with no secrets at all.
: ${INFISICAL_ENV_FALLBACK:=default}

# Left unset on purpose: it is the *resolved* environment, decided per fetch by
# _infisical_env_candidates. Setting it in the environment before the shell
# starts pins one environment and disables both the hostname lookup and the
# fallback, which is how a machine borrows another's secrets deliberately.
: ${INFISICAL_ENV=}

# Key material lives in its own folder, one secret per file: the secret's key
# is the file name and its value is the file body, so a secret called
# "id_rsa.pub" becomes ~/.ssh/id_rsa.pub. A separate folder is what makes that
# safe — at the root path a secret named "config" would become an environment
# variable, and the name exclusion below only catches names starting SSH_.
: ${INFISICAL_SSH_PATH:=/ssh}
: ${INFISICAL_SSH_DIR:=$HOME/.ssh}

# Public keys are the only thing here that is not secret. Everything else —
# private keys, config, known_hosts, authorized_keys — is written 600, which
# ssh accepts for all of them, so the default needs no per-name exceptions.
: ${INFISICAL_SSH_PUBLIC_MODE:=644}
: ${INFISICAL_SSH_PRIVATE_MODE:=600}

# Names matching this never become environment variables. The SSH keys share the
# root path with the shell variables — `infisical secrets folders create` does
# not honour --env, so a separate folder could not be made to work per
# environment — and a private key in every process's environment is not
# acceptable. Excluding by name keeps that guarantee local, independent of how
# the project is laid out.
: ${INFISICAL_ENV_EXCLUDE:='^SSH_'}

_infisical_is_configured() {
  command -v infisical >/dev/null 2>&1 \
    && command -v jq >/dev/null 2>&1 \
    && [[ -n "$INFISICAL_PROJECT_ID" ]]
}

# The CLI ignores --domain for user logins and always talks to whatever
# `infisical login` recorded, so hints and status must report that one.
_infisical_recorded_domain() {
  local domain=$(jq -r '.LoggedInUserDomain // empty' \
    "$HOME/.infisical/infisical-config.json" 2>/dev/null)
  domain=${domain%/api}
  print -r -- "${domain:-$INFISICAL_DOMAIN}"
}

_infisical_login_hint() {
  print -r -- "infisical login --domain=$(_infisical_recorded_domain)"
}

# With no valid session `infisical export` does not simply fail — it drops into
# an interactive login picker and writes that TUI to *stdout*, which lands in
# jq and surfaces as "parse error: Invalid numeric literal". This asks the same
# question read-only: it never prompts, and exits non-zero when the session is
# missing or expired.
_infisical_has_session() {
  infisical login status --silent >/dev/null 2>&1 </dev/null
}

# The environments to try, best first. An explicit INFISICAL_ENV pins the
# choice; otherwise this machine's own environment is preferred and the
# fallback is tried only if that one does not exist.
#
# There is no cheap way to ask "does this environment exist?" — `infisical
# secrets` 404s against this server even for environments that do exist, so
# existence is discovered by attempting the export and seeing it fail.
_infisical_env_candidates() {
  if [[ -n "$INFISICAL_ENV" ]]; then
    print -r -- "$INFISICAL_ENV"
    return 0
  fi

  [[ -n "$INFISICAL_HOST_ENV" ]] && print -r -- "$INFISICAL_HOST_ENV"
  [[ -n "$INFISICAL_ENV_FALLBACK" && "$INFISICAL_ENV_FALLBACK" != "$INFISICAL_HOST_ENV" ]] \
    && print -r -- "$INFISICAL_ENV_FALLBACK"

  return 0
}

# The cache records which environment produced it on its first line, so
# secrets-status can report the resolved environment without a network call.
# A comment is safe here because the cache is sourced by zsh.
_infisical_cache_env() {
  local line
  read -r line < "$INFISICAL_CACHE" 2>/dev/null || return 1
  [[ $line == '# env='* ]] || return 1
  print -r -- "${line#\# env=}"
}

_infisical_cache_is_fresh() {
  [[ -r "$INFISICAL_CACHE" ]] || return 1

  # Without zsh/stat the age is unknowable; assume fresh rather than refetch
  # on every single shell.
  zmodload -F zsh/stat b:zstat 2>/dev/null || return 0
  zmodload zsh/datetime 2>/dev/null || return 0

  local -a cache_stat
  zstat -A cache_stat +mtime -- "$INFISICAL_CACHE" || return 1
  (( EPOCHSECONDS - cache_stat[1] < INFISICAL_CACHE_MAX_AGE_HOURS * 3600 ))
}

# Fetches one environment into a staged file, so a failed export never
# truncates a good cache and the secrets are never briefly world-readable.
_infisical_fetch_env() {
  local env=$1
  local staged="${INFISICAL_CACHE}.staged.$$"

  mkdir -p -m 700 "${INFISICAL_CACHE:h}" || return 1

  # >| rather than >: under noclobber a leftover staged file from a crashed
  # shell with this same pid would make the fetch fail for good.
  : >| "$staged" && chmod 600 "$staged" || return 1

  # JSON rather than dotenv so values can be re-quoted safely with @sh, and so
  # excluded names are dropped structurally instead of by line-matching a
  # format where one secret can span many lines.
  setopt localoptions pipefail

  # `always` so an interrupt mid-fetch cannot strand a staged file; the mv on
  # the success path leaves nothing for it to remove. stdin is closed because a
  # CLI that decides to prompt must fail rather than block a login shell.
  {
    print -r -- "# env=$env" >> "$staged" || return 1

    if ! infisical export --silent --format=json \
          --domain="$INFISICAL_DOMAIN" \
          --projectId="$INFISICAL_PROJECT_ID" \
          --path=/ \
          --env="$env" \
          </dev/null \
        | jq -r --arg exclude "$INFISICAL_ENV_EXCLUDE" \
            '.[] | select(.key | test($exclude) | not)
                 | "export \(.key)=\(.value|@sh)"' \
          >> "$staged"; then
      return 1
    fi

    mv -f "$staged" "$INFISICAL_CACHE"
  } always {
    rm -f "$staged"
  }
}

# Tries each candidate environment in turn and keeps the first that exists.
#
# Returns 2 — distinct from any other failure — when the session is expired, so
# callers can say "log in again" rather than "the server is unreachable".
_infisical_write_cache() {
  _infisical_has_session || return 2

  local env
  for env in ${(f)"$(_infisical_env_candidates)"}; do
    _infisical_fetch_env "$env" && return 0
  done

  return 1
}

_infisical_load_cache() {
  [[ -r "$INFISICAL_CACHE" ]] || return 1

  # The cache carries its own `export` keywords, so no allexport games needed.
  source "$INFISICAL_CACHE"
}

# File names come straight from secret keys, so they are held to a
# conservative set. Rejecting a leading dot rules out "." and ".." outright,
# and rejecting everything but [A-Za-z0-9._-] rules out a key like
# "../../.bashrc" or "a/b" writing outside $INFISICAL_SSH_DIR.
_infisical_ssh_name_ok() {
  [[ $1 == [A-Za-z0-9_]* && $1 != *[^A-Za-z0-9._-]* ]]
}

# Writes one file at its final mode before any key material reaches it, then
# renames it into place, so a reader never sees a half-written key and no key
# is ever briefly world-readable.
_infisical_ssh_write() {
  local name=$1 json=$2 mode=$3
  local dest="$INFISICAL_SSH_DIR/$name"
  local staged="$dest.staged.$$"

  # >| throughout: an interactive zsh very often runs with noclobber, under
  # which a plain > onto the file just created fails and the fetch looks like a
  # missing folder. These files are ours and are meant to be truncated.
  {
    : >| "$staged" && chmod 600 "$staged" || return 1

    # -j, not -r: jq -r appends a newline, which would double the one most key
    # files already end with. The value lands byte for byte.
    jq -j --arg k "$name" '.[] | select(.key == $k) | .value' < "$json" >| "$staged" \
      || return 1
    [[ -s "$staged" ]] || return 1

    # ssh-keygen rejects a key whose last line is unterminated. A value that
    # already ends in a newline is left exactly as it is: the command
    # substitution strips trailing newlines, so it is empty only in that case.
    [[ -n $(tail -c1 "$staged") ]] && print >> "$staged"

    chmod "$mode" "$staged" || return 1
    mv -f "$staged" "$dest"
  } always {
    rm -f "$staged"
  }
}

# Returns 2 when the folder does not exist in this environment, so callers can
# try the next candidate; a machine with no keys of its own is not an error.
_infisical_ssh_sync() {
  local env=$1
  local json="${INFISICAL_CACHE:h}/ssh-fetch.$$.json"

  mkdir -p -m 700 "${INFISICAL_CACHE:h}" || return 1

  {
    : >| "$json" && chmod 600 "$json" || return 1

    setopt localoptions pipefail
    infisical export --silent --format=json \
        --domain="$INFISICAL_DOMAIN" \
        --projectId="$INFISICAL_PROJECT_ID" \
        --path="$INFISICAL_SSH_PATH" \
        --env="$env" \
        </dev/null >| "$json" 2>/dev/null || return 2

    local -a names
    names=( ${(f)"$(jq -r '.[].key' < "$json" 2>/dev/null)"} )
    (( ${#names} )) || return 2

    # Created at 700 and enforced at 700: ssh refuses to use a private key from
    # a directory others can reach.
    mkdir -p -m 700 "$INFISICAL_SSH_DIR" || return 1
    chmod 700 "$INFISICAL_SSH_DIR" || return 1

    local name mode
    local -a wrote
    local -i failed=0
    for name in $names; do
      if ! _infisical_ssh_name_ok "$name"; then
        print -u2 "ssh: refusing to write $INFISICAL_SSH_PATH/$name — unsafe file name"
        (( failed++ ))
        continue
      fi

      case $name in
        *.pub) mode=$INFISICAL_SSH_PUBLIC_MODE ;;
        *)     mode=$INFISICAL_SSH_PRIVATE_MODE ;;
      esac

      if _infisical_ssh_write "$name" "$json" "$mode"; then
        wrote+=( "$name ($mode)" )
      else
        print -u2 "ssh: failed to write $name"
        (( failed++ ))
      fi
    done

    (( ${#wrote} )) && print "ssh: ${(j:, :)wrote} -> $INFISICAL_SSH_DIR (from $env:$INFISICAL_SSH_PATH)"
    (( failed == 0 ))
  } always {
    rm -f "$json"
  }
}

# Rewrites $INFISICAL_SSH_DIR from the key material in $INFISICAL_SSH_PATH.
# Files are overwritten; nothing is ever deleted, so a key removed from the
# project stays on disk until it is removed by hand.
secrets-ssh-sync() {
  if ! _infisical_is_configured; then
    print -u2 "ssh: infisical not on PATH, or INFISICAL_PROJECT_ID is unset"
    return 1
  fi

  if ! _infisical_has_session; then
    print -u2 "ssh: Infisical session expired — run: $(_infisical_login_hint)"
    return 1
  fi

  local env
  local -i rc=0
  for env in ${(f)"$(_infisical_env_candidates)"}; do
    _infisical_ssh_sync "$env"
    rc=$?
    (( rc == 2 )) || return $rc
  done

  print -u2 "ssh: no $INFISICAL_SSH_PATH folder in any candidate environment"
  return 1
}

secrets-refresh() {
  if ! _infisical_is_configured; then
    print -u2 "secrets: infisical not on PATH, or INFISICAL_PROJECT_ID is unset"
    return 1
  fi

  _infisical_write_cache
  case $? in
    0) ;;
    2) print -u2 "secrets: Infisical session expired — run: $(_infisical_login_hint)"
       return 1 ;;
    *) print -u2 "secrets: export failed — check the server, project id and env"
       return 1 ;;
  esac

  _infisical_load_cache
}

secrets-status() {
  if [[ ! -r "$INFISICAL_CACHE" ]]; then
    print "secrets: no cache at $INFISICAL_CACHE"
    return 1
  fi

  local freshness=stale
  _infisical_cache_is_fresh && freshness=fresh

  local session=expired
  _infisical_has_session && session=valid

  # Count assignments, not lines — a multi-line value would inflate a line count.
  local -i count=$(grep -cE '^export [A-Za-z_][A-Za-z0-9_]*=' "$INFISICAL_CACHE")

  local env=$(_infisical_cache_env)
  local origin
  case $env in
    "")                       env=unknown; origin="cache predates env tracking" ;;
    "$INFISICAL_HOST_ENV")    origin="this machine" ;;
    "$INFISICAL_ENV_FALLBACK") origin="fallback, no environment named $INFISICAL_HOST_ENV" ;;
    *)                        origin="pinned via INFISICAL_ENV" ;;
  esac

  print "secrets: $count entries, cache $freshness, session $session, from $(_infisical_recorded_domain)"
  print "  environment: $env ($origin)"
  [[ $session == valid ]] || print "  run: $(_infisical_login_hint)"
}

secrets-forget() {
  rm -f "$INFISICAL_CACHE"
}

_infisical_load_at_startup() {
  _infisical_is_configured || return 0

  local -i rc=0
  if ! _infisical_cache_is_fresh; then
    _infisical_write_cache
    rc=$?

    # Tied to the refetch rather than to every shell: ~/.ssh is rewritten on
    # the same 12h cadence as the cache, so a new machine gets its keys at
    # first shell without every shell paying for it. The environment is taken
    # from the cache just written, so files and variables always agree.
    (( rc == 0 )) && _infisical_ssh_sync "$(_infisical_cache_env)"
  fi

  # An expired session is only worth a word once the cached values have loaded;
  # with no cache at all the message below already says to log in.
  if ! _infisical_load_cache; then
    print -u2 "secrets: no Infisical cache — run: $(_infisical_login_hint) && secrets-refresh"
  elif (( rc == 2 )); then
    print -u2 "secrets: Infisical session expired, using cached values — run: $(_infisical_login_hint)"
  fi
}

_infisical_load_at_startup
