#!/usr/bin/env bash
# Entrypoint for the `proxy` container: runs squid (egress allowlist),
# domain-gate (runtime, session-scoped allowlist additions -- see
# containers/proxy/domain-gate/main.go) and nginx (Ollama API gate,
# currently disabled) as supervised children of this script, which is
# PID 1. Any process dying brings the whole container down (fail-closed
# rather than silently losing one gate).
set -euo pipefail

#: "${OLLAMA_UPSTREAM:?OLLAMA_UPSTREAM must be set (e.g. host.docker.internal:11434) — see compose.yaml}"

RUNTIME_DIR=/tmp/proxy-runtime
mkdir -p "$RUNTIME_DIR" /tmp/squid-cache
chmod 700 "$RUNTIME_DIR"

# Session-scoped request-domain grants (domain-gate, see
# containers/proxy/domain-gate/main.go) live on the proxy-domains named
# volume at /var/lib/proxy-domains, not tmpfs -- see compose.yaml. By
# default (PI_SANDBOX__PERSIST_DOMAINS unset/0) every grant is wiped on
# container start, same observable behavior as the old tmpfs-backed file;
# set PI_SANDBOX__PERSIST_DOMAINS=1 (start-agent.sh's --persist-domains
# flag) to keep grants across restarts instead. squid refuses to start if
# an acl's dstdomain file is missing, so this must exist either way before
# squid starts below.
DOMAINS_DIR=/var/lib/proxy-domains
DOMAINS_FILE="$DOMAINS_DIR/dynamic-domains.txt"
mkdir -p "$DOMAINS_DIR"
if [ "${PI_SANDBOX__PERSIST_DOMAINS:-0}" = "1" ]; then
  : >>"$DOMAINS_FILE" # create if missing, keep existing contents otherwise
else
  : >"$DOMAINS_FILE" # fresh, empty dynamic allowlist every container start
fi

# Render the nginx gate config with the platform-specific Ollama
# upstream address (spec §3.3/§9 — this differs between Colima and
# native NixOS Docker, so it's resolved at container start, not baked
# into the image).
# envsubst "${OLLAMA_UPSTREAM}" </etc/proxy/ollama-gate.nginx.conf.template \
#   >"$RUNTIME_DIR/ollama-gate.nginx.conf"

# Squid needs an initialized (but empty, since cache is denied) spool
# layout on first run.
if [ ! -d /var/spool/squid ]; then
  mkdir -p /var/spool/squid
fi

pids=()

squid -f /etc/proxy/squid.conf -N -d 1 &
pids+=("$!")

# domain-gate: the only writer of dynamic-domains.txt and the only
# process that issues `squid -k reconfigure` -- see
# containers/proxy/domain-gate/main.go. Listens on the internal compose
# network only (0.0.0.0:8081, not published in compose.yaml).
domain-gate &
pids+=("$!")

# TODO: This is deprecated, but may come back as the options for local AI improve/the economics get worse.
#nginx -c "$RUNTIME_DIR/ollama-gate.nginx.conf" -g "daemon off;" &
#pids+=("$!")

term_handler() {
  echo "proxy: received signal, shutting down children" >&2
  for pid in "${pids[@]}"; do
    kill -TERM "$pid" 2>/dev/null || true
  done
  wait
  exit 0
}
trap term_handler TERM INT

# If any child exits, tear the whole container down rather than run
# degraded with only one gate active.
wait -n "${pids[@]}"
echo "proxy: a supervised process exited — shutting down" >&2
term_handler
