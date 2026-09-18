#!/usr/bin/env bash
# Entrypoint for the `proxy` container: runs squid (egress allowlist)
# and nginx (Ollama API gate) as two supervised children of this
# script, which is PID 1. Either process dying brings the whole
# container down (fail-closed rather than silently losing one gate).
set -euo pipefail

: "${OLLAMA_UPSTREAM:?OLLAMA_UPSTREAM must be set (e.g. host.docker.internal:11434) — see compose.yaml}"

RUNTIME_DIR=/tmp/proxy-runtime
mkdir -p "$RUNTIME_DIR" /tmp/squid-cache
chmod 700 "$RUNTIME_DIR"

# Render the nginx gate config with the platform-specific Ollama
# upstream address (spec §3.3/§9 — this differs between Colima and
# native NixOS Docker, so it's resolved at container start, not baked
# into the image).
envsubst "${OLLAMA_UPSTREAM}" </etc/proxy/ollama-gate.nginx.conf.template \
  >"$RUNTIME_DIR/ollama-gate.nginx.conf"

# Squid needs an initialized (but empty, since cache is denied) spool
# layout on first run.
if [ ! -d /var/spool/squid ]; then
  mkdir -p /var/spool/squid
fi

pids=()

squid -f /etc/proxy/squid.conf -N -d 1 &
pids+=("$!")

nginx -c "$RUNTIME_DIR/ollama-gate.nginx.conf" -g "daemon off;" &
pids+=("$!")

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
