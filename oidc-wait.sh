#!/bin/sh
# Entrypoint wrapper. MCPHub registers its OIDC provider once at start and skips it for
# good ("Provider skipped") if the IdP does not answer the discovery request at that moment,
# e.g. after a host reboot where MCPHub comes up before the IdP. So wait (bounded) for the
# discovery URL, then hand over to the upstream entrypoint, which is kept as
# entrypoint-upstream.sh (see Dockerfile).
#
# OIDC_WAIT_SECONDS: max wait, default 300, 0 disables. After the timeout MCPHub starts anyway,
# so a dead IdP cannot lock out the local admin fallback.
# shortcut: only an env-provided discovery URL is watched, one set in mcp_settings.json is not.
url=${BETTER_AUTH_OIDC_DISCOVERY_URL:-${OIDC_DISCOVERY_URL:-}}
max=${OIDC_WAIT_SECONDS:-300}

case "${BETTER_AUTH_OIDC_ENABLED:-}" in false | 0 | no | off | FALSE | False) url= ;; esac
case "$max" in '' | *[!0-9]*) max=300 ;; esac

if [ -n "$url" ] && [ "$max" -gt 0 ]; then
  waited=0
  until curl -fsS -m 5 -o /dev/null "$url" 2>/dev/null; do
    if [ "$waited" -ge "$max" ]; then
      echo "oidc-wait: no answer from $url after ${max}s, starting anyway" >&2
      break
    fi
    [ "$waited" -eq 0 ] && echo "oidc-wait: waiting for OIDC discovery at $url" >&2
    sleep 5
    waited=$((waited + 5))
  done
fi

exec /usr/local/bin/entrypoint-upstream.sh "$@"
