#!/bin/bash

# @lib: printing-and-output

set -euo pipefail

DEFAULT_LOCAL_PORT="53692"
DEFAULT_REMOTE_HOST="192.168.86.41"
DEFAULT_REMOTE_PORT="53692"

show_help () {
  echo "Usage: $0 [OPTIONS]"
  echo ""
  echo "One-shot TCP forward from a local port to the UTM VM, so a"
  echo "loopback callback on this host reaches the VM."
  echo ""
  echo ""
  echo "OPTIONS:"
  echo "  --local-port PORT     Local port to listen on (default: ${DEFAULT_LOCAL_PORT})"
  echo "  --remote-host HOST    UTM VM address to forward to (default: ${DEFAULT_REMOTE_HOST})"
  echo "  --remote-port PORT    Port on the UTM VM to forward to (default: ${DEFAULT_REMOTE_PORT})"
  echo "  --help, -h            Show this help"
}

local_port="${DEFAULT_LOCAL_PORT}"
remote_host="${DEFAULT_REMOTE_HOST}"
remote_port="${DEFAULT_REMOTE_PORT}"

while [[ $# -gt 0 ]]; do
  case $1 in
    --local-port)
    local_port="$2"
    shift 2
    ;;
    --remote-host)
    remote_host="$2"
    shift 2
    ;;
    --remote-port)
    remote_port="$2"
    shift 2
    ;;
    --help|-h)
    show_help
    exit 0
    ;;
    *)
    print_error "Unknown option: $1"
    exit 1
    ;;
  esac
done

print_debug "Local port: ${local_port}"
print_debug "Remote host: ${remote_host}"
print_debug "Remote port: ${remote_port}"

print_status "Forwarding localhost:${local_port} to ${remote_host}:${remote_port}"

exec socat "TCP-LISTEN:${local_port},reuseaddr" "TCP:${remote_host}:${remote_port}"