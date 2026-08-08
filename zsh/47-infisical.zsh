# Secrets come from Infisical, never from this repo.
# The export is cached on disk so opening a shell costs no network round-trip.
#
#   secrets-refresh   re-fetch now and reload into this shell
#   secrets-status    where the cache came from and whether it is stale
#   secrets-forget    delete the cache
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
: ${INFISICAL_ENV:=prod}
: ${INFISICAL_CACHE:=$HOME/.cache/infisical/env}
: ${INFISICAL_CACHE_MAX_AGE_HOURS:=12}

# Names matching this never become environment variables. The SSH keys share the
# root path with the shell variables — `infisical secrets folders create` does
# not honour --env, so a separate folder could not be made to work in prod — and
# a private key in every process's environment is not acceptable. Excluding by
# name keeps that guarantee local, independent of how the project is laid out.
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

# Fetches into a staged file so a failed export never truncates a good cache,
# and so the secrets are never briefly world-readable.
#
# Returns 2 — distinct from any other failure — when the session is expired, so
# callers can say "log in again" rather than "the server is unreachable".
_infisical_write_cache() {
  _infisical_has_session || return 2

  local staged="${INFISICAL_CACHE}.staged.$$"

  mkdir -p -m 700 "${INFISICAL_CACHE:h}" || return 1
  : > "$staged" && chmod 600 "$staged" || return 1

  # JSON rather than dotenv so values can be re-quoted safely with @sh, and so
  # excluded names are dropped structurally instead of by line-matching a
  # format where one secret can span many lines.
  setopt localoptions pipefail

  # `always` so an interrupt mid-fetch cannot strand a staged file; the mv on
  # the success path leaves nothing for it to remove. stdin is closed because a
  # CLI that decides to prompt must fail rather than block a login shell.
  {
    if ! infisical export --silent --format=json \
          --domain="$INFISICAL_DOMAIN" \
          --projectId="$INFISICAL_PROJECT_ID" \
          --path=/ \
          --env="$INFISICAL_ENV" \
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

_infisical_load_cache() {
  [[ -r "$INFISICAL_CACHE" ]] || return 1

  # The cache carries its own `export` keywords, so no allexport games needed.
  source "$INFISICAL_CACHE"
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

  print "secrets: $count entries, cache $freshness, session $session, from $(_infisical_recorded_domain) ($INFISICAL_ENV)"
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
