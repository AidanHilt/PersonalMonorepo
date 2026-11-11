#!/usr/bin/env bash
# socat EXEC: handler for S1's network-approval spike. Invoked per TCP
# connection with stdin/stdout wired to the socket; reads one unsigned
# webhook request, checks the path carries the expected token, logs it,
# and answers per a small per-host policy.
set -u

IFS= read -r request_line
request_line="${request_line%$'\r'}"
req_method=""
req_path=""
read -r req_method req_path _ <<<"$request_line"
: "$req_method"

content_length=0
while IFS= read -r header_line; do
  header_line="${header_line%$'\r'}"
  if [[ -z "$header_line" ]]; then
    break
  fi
  case "${header_line,,}" in
  content-length:*)
    content_length="${header_line#*:}"
    content_length="${content_length// /}"
    ;;
  esac
done

if [[ "$req_path" != "/${SPIKE_TOKEN:?SPIKE_TOKEN not set}" ]]; then
  printf 'HTTP/1.1 404 Not Found\r\n'
  printf 'Content-Length: 0\r\n'
  printf 'Connection: close\r\n'
  printf '\r\n'
  exit 0
fi

body=""
if [[ "$content_length" -gt 0 ]]; then
  body="$(head -c "$content_length")"
fi

body_compact="$(printf '%s' "$body" | jq -c . 2>/dev/null)"
if [[ -z "$body_compact" ]]; then
  body_compact='{}'
fi

printf '%s\n' "$body_compact" >>"${SPIKE_LOG:?SPIKE_LOG not set}"

host="$(printf '%s' "$body_compact" | jq -r '.request.host // empty')"

case "$host" in
example.com)
  decision_body='{"decision":"granted"}'
  ;;
example.org)
  decision_body='{"decision":"denied","reason":"spike policy"}'
  ;;
httpbin.org)
  decision_body='{"decision":"granted_session"}'
  ;;
*)
  decision_body='{"decision":"denied","reason":"unknown host"}'
  ;;
esac

content_len=${#decision_body}

printf 'HTTP/1.1 200 OK\r\n'
printf 'Content-Type: application/json\r\n'
printf 'Content-Length: %s\r\n' "$content_len"
printf 'Connection: close\r\n'
printf '\r\n'
printf '%s' "$decision_body"
