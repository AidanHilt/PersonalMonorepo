#!/bin/bash

# @lib: printing-and-output
# @lib: args-and-help

set -euo pipefail

DEFAULT_LOCAL_PORT="53692"
DEFAULT_REMOTE_HOST="192.168.86.41"
DEFAULT_REMOTE_PORT="53692"

local_port="${DEFAULT_LOCAL_PORT}"
remote_host="${DEFAULT_REMOTE_HOST}"
remote_port="${DEFAULT_REMOTE_PORT}"

args_description "One-shot TCP forward from a local port to the UTM VM, so a loopback callback on this host reaches the VM."
args_value "" "--local-port" local_port "PORT" "Local port to listen on (default: ${DEFAULT_LOCAL_PORT})"
args_value "" "--remote-host" remote_host "HOST" "UTM VM address to forward to (default: ${DEFAULT_REMOTE_HOST})"
args_value "" "--remote-port" remote_port "PORT" "Port on the UTM VM to forward to (default: ${DEFAULT_REMOTE_PORT})"

args_parse "$@" || {
  rc=$?
  exit "$(args_rc "$rc")"
}

print_debug "Local port: ${local_port}"
print_debug "Remote host: ${remote_host}"
print_debug "Remote port: ${remote_port}"

print_status "Forwarding localhost:${local_port} to ${remote_host}:${remote_port}"

exec ssh -N -L "${local_port}:127.0.0.1:${remote_port}" "aidan@${remote_host}"
