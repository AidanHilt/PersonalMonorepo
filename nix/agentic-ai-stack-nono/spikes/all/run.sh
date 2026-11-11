#!/usr/bin/env bash
# Spike harness: answers nono (>=0.81.0) feasibility questions -- network
# approval, a pi-like runtime under the proxy, filesystem rules, the nix
# daemon, and sessions. Usage: bash run.sh [--with-pi-user]
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

nono_version_ok() {
  if ! command -v nono >/dev/null 2>&1; then
    return 1
  fi
  local version_string
  version_string="$(nono --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -n1)"
  if [[ -z "$version_string" ]]; then
    return 1
  fi
  local major minor
  IFS='.' read -r major minor _ <<<"$version_string"
  if ((major > 0)); then
    return 0
  fi
  if ((minor >= 81)); then
    return 0
  fi
  return 1
}

if [[ -z "${RUN_SH_REEXEC:-}" ]]; then
  missing=()
  for dep in socat jq curl; do
    if ! command -v "$dep" >/dev/null 2>&1; then
      missing+=("$dep")
    fi
  done
  if ! nono_version_ok; then
    missing+=("nono>=0.81.0")
  fi

  if [[ ${#missing[@]} -gt 0 ]]; then
    export RUN_SH_REEXEC=1
    if nix shell github:nolabs-ai/nono#prebuilt nixpkgs#socat nixpkgs#jq nixpkgs#curl nixpkgs#coreutils nixpkgs#nodejs -c bash "$SCRIPT_DIR/run.sh" "$@"; then
      exit 0
    fi
    echo "ERR nono flake ref or nix shell failed"
    exit 1
  fi
fi

WITH_PI_USER=0
for arg in "$@"; do
  if [[ "$arg" == "--with-pi-user" ]]; then
    WITH_PI_USER=1
  fi
done

PASS_COUNT=0
TOTAL_COUNT=0
OUTPUT_LINES=()
DETACHED_NAMES=()

emit() {
  OUTPUT_LINES+=("$1")
  printf '%s\n' "$1"
}

report() {
  local id="$1" status="$2" name="$3" detail="${4:-}" maxlen="${5:-100}"
  detail="${detail:0:$maxlen}"
  if [[ "$status" == "PASS" ]]; then
    PASS_COUNT=$((PASS_COUNT + 1))
    TOTAL_COUNT=$((TOTAL_COUNT + 1))
  elif [[ "$status" == "FAIL" ]]; then
    TOTAL_COUNT=$((TOTAL_COUNT + 1))
  fi
  emit "$id $status $name :: $detail"
}

last_line() {
  local target="$1"
  if [[ -f "$target" ]]; then
    tail -n1 "$target" | tr -d '\r'
  fi
}

WORKDIR="$(mktemp -d)"
LOGDIR="$WORKDIR/logs"
mkdir -p "$LOGDIR"

cleanup() {
  local rc=$?
  if [[ -n "${SOCAT_PID:-}" ]]; then
    kill "$SOCAT_PID" >/dev/null 2>&1
  fi
  local name
  for name in "${DETACHED_NAMES[@]}"; do
    if [[ -n "$name" ]]; then
      timeout 20 nono stop "$name" >/dev/null 2>&1
    fi
  done
  rm -rf "$WORKDIR"
  exit "$rc"
}
trap cleanup EXIT INT TERM

gen_profile() {
  local out="$1" sock="$2"
  sed "s#__SOCKET__#$sock#" "$SCRIPT_DIR/approval.template.json" >"$out"
}

# --- S1: network approval ---------------------------------------------------

SOCKDIR="$WORKDIR/sock"
mkdir -p "$SOCKDIR"
chmod 700 "$SOCKDIR"
SOCK="$SOCKDIR/s.sock"
export SPIKE_LOG="$WORKDIR/requests.log"
: >"$SPIKE_LOG"

HANDLER="$SCRIPT_DIR/handler.sh"
chmod +x "$HANDLER" 2>/dev/null

timeout 65 socat UNIX-LISTEN:"$SOCK",fork,mode=600 EXEC:"$HANDLER" >"$LOGDIR/socat.log" 2>&1 &
SOCAT_PID=$!
sleep 1

PROFDIR="$WORKDIR/profiles"
mkdir -p "$PROFDIR"

PROFILE1="$PROFDIR/s1.json"
gen_profile "$PROFILE1" "$SOCK"

timeout 60 nono profile validate --profile "$PROFILE1" >"$LOGDIR/s1.1.log" 2>&1
rc=$?
if [[ $rc -eq 0 ]]; then
  report S1.1 PASS "nono profile validate" "ok"
else
  report S1.1 FAIL "nono profile validate" "$(last_line "$LOGDIR/s1.1.log")"
fi

code="$(timeout 60 nono run --profile "$PROFILE1" -- curl -sS --max-time 20 -o /dev/null -w '%{http_code}' https://example.com 2>"$LOGDIR/s1.2.log")"
rc=$?
if [[ $rc -eq 0 ]] && { [[ "$code" == 200 ]] || [[ "$code" == 3?? ]]; } && grep -q '"host":"example.com"' "$SPIKE_LOG" 2>/dev/null; then
  report S1.2 PASS "curl example.com granted" "code=$code"
else
  report S1.2 FAIL "curl example.com granted" "code=$code rc=$rc $(last_line "$LOGDIR/s1.2.log")"
fi

timeout 60 nono run --profile "$PROFILE1" -- curl -sS --max-time 20 -o /dev/null https://example.org >"$LOGDIR/s1.3.log" 2>&1
rc=$?
if [[ $rc -ne 0 ]] && grep -q '"host":"example.org"' "$SPIKE_LOG" 2>/dev/null; then
  report S1.3 PASS "curl example.org denied" "rc=$rc"
else
  report S1.3 FAIL "curl example.org denied" "rc=$rc $(last_line "$LOGDIR/s1.3.log")"
fi

out="$(timeout 60 nono run --profile "$PROFILE1" -- sh -c 'curl -sS --max-time 20 -o /dev/null -w "%{http_code} " https://httpbin.org/status/200 && curl -sS --max-time 20 -o /dev/null -w "%{http_code}" https://httpbin.org/status/200' 2>"$LOGDIR/s1.4.log")"
rc=$?
count="$(grep -c '"host":"httpbin.org"' "$SPIKE_LOG" 2>/dev/null)"
if [[ $rc -eq 0 && "$out" == "200 200" && "$count" -eq 1 ]]; then
  report S1.4 PASS "two httpbin calls, single ask" "count=$count out=$out"
else
  report S1.4 FAIL "two httpbin calls, single ask" "count=$count out=$out rc=$rc $(last_line "$LOGDIR/s1.4.log")"
fi

timeout 60 nono run --profile "$PROFILE1" -- curl --noproxy '*' -sS --max-time 20 https://example.com >"$LOGDIR/s1.5.log" 2>&1
rc=$?
if [[ $rc -ne 0 ]]; then
  report S1.5 PASS "curl bypassing proxy fails" "rc=$rc"
else
  report S1.5 FAIL "curl bypassing proxy fails" "rc=$rc $(last_line "$LOGDIR/s1.5.log")"
fi

before_count="$(wc -l <"$SPIKE_LOG")"
timeout 60 nono run --profile "$PROFILE1" -- curl -sS --max-time 20 http://169.254.169.254/ >"$LOGDIR/s1.6.log" 2>&1
rc=$?
after_count="$(wc -l <"$SPIKE_LOG")"
if [[ $rc -ne 0 && "$after_count" -eq "$before_count" ]]; then
  report S1.6 PASS "metadata IP blocked, not asked" "rc=$rc"
else
  report S1.6 FAIL "metadata IP blocked, not asked" "rc=$rc before=$before_count after=$after_count $(last_line "$LOGDIR/s1.6.log")"
fi

timeout 60 nono run --profile "$PROFILE1" -- touch "$SOCKDIR/x" >"$LOGDIR/s1.7.log" 2>&1
rc=$?
if [[ $rc -ne 0 && ! -e "$SOCKDIR/x" ]]; then
  report S1.7 PASS "touch sock dir fails" "rc=$rc"
else
  report S1.7 FAIL "touch sock dir fails" "rc=$rc $(last_line "$LOGDIR/s1.7.log")"
fi

PROFILE1B="$PROFDIR/s1-badsock.json"
gen_profile "$PROFILE1B" "$SOCKDIR/does-not-exist.sock"
timeout 60 nono run --profile "$PROFILE1B" -- curl -sS --max-time 20 https://example.com >"$LOGDIR/s1.8.log" 2>&1
rc=$?
if [[ $rc -ne 0 ]]; then
  report S1.8 PASS "fail-closed on missing socket" "rc=$rc"
else
  report S1.8 FAIL "fail-closed on missing socket" "rc=$rc $(last_line "$LOGDIR/s1.8.log")"
fi

first_line="$(head -n1 "$SPIKE_LOG" 2>/dev/null)"
first_compact="$(printf '%s' "$first_line" | jq -c . 2>/dev/null)"
if [[ -z "$first_compact" ]]; then
  first_compact="$first_line"
fi
report S1.9 INFO "first request body" "$first_compact" 300

# --- S2: pi-like runtime under the proxy ------------------------------------

timeout 60 nono run --profile "$PROFILE1" -- getent hosts example.com >"$LOGDIR/s2.1.log" 2>&1
rc=$?
report S2.1 INFO "getent hosts example.com" "rc=$rc $(last_line "$LOGDIR/s2.1.log")"

NODE_FETCH_JS='fetch("https://example.com").then(function(r){process.exit(r.ok?0:1)}).catch(function(){process.exit(1)})'

timeout 60 nono run --profile "$PROFILE1" -- env NODE_USE_ENV_PROXY=1 node -e "$NODE_FETCH_JS" >"$LOGDIR/s2.2.log" 2>&1
rc=$?
if [[ $rc -eq 0 ]]; then
  report S2.2 PASS "node fetch w/ NODE_USE_ENV_PROXY" "rc=$rc"
else
  report S2.2 FAIL "node fetch w/ NODE_USE_ENV_PROXY" "rc=$rc $(last_line "$LOGDIR/s2.2.log")"
fi

timeout 60 nono run --profile "$PROFILE1" -- node -e "$NODE_FETCH_JS" >"$LOGDIR/s2.3.log" 2>&1
rc=$?
if [[ $rc -eq 0 ]]; then
  report S2.3 INFO "node fetch without env proxy" "succeeded rc=$rc"
else
  report S2.3 INFO "node fetch without env proxy" "failed rc=$rc $(last_line "$LOGDIR/s2.3.log")"
fi

if command -v pi >/dev/null 2>&1; then
  timeout 60 nono run --profile "$PROFILE1" -- pi --version >"$LOGDIR/s2.4.log" 2>&1
  rc=$?
  report S2.4 INFO "pi --version inside nono" "rc=$rc $(last_line "$LOGDIR/s2.4.log")"
else
  report S2.4 SKIP "pi --version inside nono" "pi not on PATH"
fi

# --- S3: filesystem rules ----------------------------------------------------

FSDIR="$WORKDIR/d"
mkdir -p "$FSDIR"
printf 'secret\n' >"$FSDIR/secret.txt"
printf 'ok\n' >"$FSDIR/ok.txt"

PROFILE3A="$PROFDIR/s3-deny-within-allow.json"
jq -n --arg dir "$FSDIR" '{
  "extends": "default",
  "meta": {"name": "spike-s3-deny-within-allow"},
  "groups": {"include": []},
  "workdir": {"access": "none"},
  "filesystem": {"allow": [$dir], "read": [$dir], "deny": [($dir + "/secret.txt")], "unix_socket": []}
}' >"$PROFILE3A"

timeout 60 nono run --profile "$PROFILE3A" -- cat "$FSDIR/secret.txt" >"$LOGDIR/s3.1.secret.log" 2>&1
secret_rc=$?
timeout 60 nono run --profile "$PROFILE3A" -- cat "$FSDIR/ok.txt" >"$LOGDIR/s3.1.ok.log" 2>&1
ok_rc=$?

if [[ $secret_rc -eq 0 && $ok_rc -eq 0 ]]; then
  fs_state="started, deny NOT enforced"
elif [[ $secret_rc -ne 0 && $ok_rc -eq 0 ]]; then
  fs_state="started, deny enforced"
elif [[ $secret_rc -ne 0 && $ok_rc -ne 0 ]]; then
  fs_state="start refused"
else
  fs_state="ambiguous"
fi
report S3.1 INFO "deny-within-allow" "$fs_state; $(last_line "$LOGDIR/s3.1.secret.log")"

base_closure_file="$WORKDIR/closure_base.txt"
: >"$base_closure_file"

add_closure() {
  local target="$1" bin="$2"
  if [[ -n "$bin" && -e "$bin" ]]; then
    timeout 60 nix-store -qR "$bin" >>"$target" 2>>"$LOGDIR/closure.err"
  fi
}

coreutils_bin=""
if command -v true >/dev/null 2>&1; then
  coreutils_bin="$(command -v true)"
fi

add_closure "$base_closure_file" "$(command -v bash)"
add_closure "$base_closure_file" "$(command -v ls)"
add_closure "$base_closure_file" "$coreutils_bin"
add_closure "$base_closure_file" "$(command -v curl)"
sort -u "$base_closure_file" -o "$base_closure_file"

closure_file="$WORKDIR/closure_full.txt"
cp "$base_closure_file" "$closure_file"

pad_sources=()
if command -v nix >/dev/null 2>&1; then
  pad_sources+=("nixpkgs#nix")
fi
if [[ -e /run/current-system ]]; then
  pad_sources+=("/run/current-system")
fi
if [[ -e "$HOME/.nix-profile" ]]; then
  pad_sources+=("$HOME/.nix-profile")
fi

for src in "${pad_sources[@]}"; do
  current_count="$(wc -l <"$closure_file")"
  if [[ "$current_count" -ge 12000 ]]; then
    break
  fi
  if [[ "$src" == nixpkgs#* ]]; then
    built_path="$(timeout 60 nix build "$src" --no-link --print-out-paths 2>>"$LOGDIR/closure.err")"
    if [[ -n "$built_path" ]]; then
      timeout 60 nix-store -qR "$built_path" >>"$closure_file" 2>>"$LOGDIR/closure.err"
    fi
  else
    timeout 60 nix-store -qR "$src" >>"$closure_file" 2>>"$LOGDIR/closure.err"
  fi
  sort -u "$closure_file" -o "$closure_file"
done

total_closure="$(wc -l <"$closure_file")"
true_bin="$(command -v true)"

for n in 100 500 1000 2000 5000 10000; do
  if [[ "$n" -gt "$total_closure" ]]; then
    continue
  fi
  subset_file="$WORKDIR/closure_$n.txt"
  head -n "$n" "$closure_file" >"$subset_file"
  reads_json="$(jq -R -s -c 'split("\n") | map(select(length > 0))' "$subset_file")"

  profile_n="$PROFDIR/s3-closure-$n.json"
  jq -n --argjson reads "$reads_json" '{
    "extends": "default",
    "meta": {"name": "spike-s3-closure"},
    "groups": {"include": []},
    "workdir": {"access": "none"},
    "filesystem": {"allow": [], "read": $reads, "deny": [], "unix_socket": []}
  }' >"$profile_n"

  start_ts="$(date +%s)"
  timeout 60 nono run --profile "$profile_n" -- "$true_bin" >"$LOGDIR/s3.2.$n.log" 2>&1
  rc=$?
  end_ts="$(date +%s)"
  elapsed=$((end_ts - start_ts))

  if [[ $rc -eq 0 ]]; then
    report S3.2 INFO "closure N=$n" "ok, ${elapsed}s"
  else
    report S3.2 INFO "closure N=$n" "failed, ${elapsed}s $(last_line "$LOGDIR/s3.2.$n.log")"
    break
  fi
done

hello_path="$(timeout 60 nix build nixpkgs#hello --no-link --print-out-paths 2>"$LOGDIR/s3.3.build.log")"
build_rc=$?
if [[ $build_rc -ne 0 || -z "$hello_path" ]]; then
  report S3.3 FAIL "hello outside closure fails" "could not build nixpkgs#hello, rc=$build_rc $(last_line "$LOGDIR/s3.3.build.log")"
else
  hello_bin="$hello_path/bin/hello"
  reads_json="$(jq -R -s -c 'split("\n") | map(select(length > 0))' "$base_closure_file")"
  profile3c="$PROFDIR/s3-exec-ceiling.json"
  jq -n --argjson reads "$reads_json" '{
    "extends": "default",
    "meta": {"name": "spike-s3-exec-ceiling"},
    "groups": {"include": []},
    "workdir": {"access": "none"},
    "filesystem": {"allow": [], "read": $reads, "deny": [], "unix_socket": []}
  }' >"$profile3c"

  timeout 60 nono run --profile "$profile3c" -- "$hello_bin" >"$LOGDIR/s3.3.hello.log" 2>&1
  hello_rc=$?
  if [[ $hello_rc -ne 0 ]]; then
    report S3.3 PASS "hello outside closure fails" "rc=$hello_rc"
  else
    report S3.3 FAIL "hello outside closure fails" "rc=$hello_rc"
  fi

  echo_bin="/bin/echo"
  if command -v echo >/dev/null 2>&1; then
    echo_bin="$(command -v echo)"
  fi
  timeout 60 nono run --profile "$profile3c" -- "$echo_bin" hi >"$LOGDIR/s3.4.echo.log" 2>&1
  echo_rc=$?
  if [[ $echo_rc -eq 0 ]]; then
    report S3.4 PASS "coreutils echo inside closure succeeds" "rc=$echo_rc"
  else
    report S3.4 FAIL "coreutils echo inside closure succeeds" "rc=$echo_rc $(last_line "$LOGDIR/s3.4.echo.log")"
  fi

  if command -v patchelf >/dev/null 2>&1; then
    loader="$(timeout 20 patchelf --print-interpreter "$hello_bin" 2>"$LOGDIR/s3.5.loader.err")"
    if [[ -n "$loader" ]]; then
      timeout 60 nono run --profile "$profile3c" -- "$loader" "$hello_bin" >"$LOGDIR/s3.5.loader.log" 2>&1
      loader_rc=$?
      report S3.5 INFO "ld.so loader trick" "rc=$loader_rc"
    else
      report S3.5 INFO "ld.so loader trick" "skipped, no interpreter resolved"
    fi
  else
    report S3.5 INFO "ld.so loader trick" "skipped, patchelf not found"
  fi
fi

# --- S4: nix daemon inside nono ----------------------------------------------

DAEMON_SOCK="/nix/var/nix/daemon-socket/socket"
if [[ ! -e "$DAEMON_SOCK" ]]; then
  report S4.1 SKIP "nix build inside nono" "daemon socket not found at $DAEMON_SOCK"
  report S4.2 SKIP "nix eval inside nono" "daemon socket not found at $DAEMON_SOCK"
else
  profile4="$PROFDIR/s4-daemon.json"
  jq -n --arg sock "$DAEMON_SOCK" '{
    "extends": "default",
    "meta": {"name": "spike-s4-nix-daemon"},
    "groups": {"include": ["nix_runtime"]},
    "workdir": {"access": "none"},
    "filesystem": {"allow": [], "read": ["/nix/store"], "deny": [], "unix_socket": [$sock]}
  }' >"$profile4"

  timeout 60 nono run --profile "$profile4" -- nix build nixpkgs#hello --no-link >"$LOGDIR/s4.1.log" 2>&1
  rc=$?
  if [[ $rc -eq 0 ]]; then
    report S4.1 INFO "nix build inside nono" "ok"
  else
    report S4.1 INFO "nix build inside nono" "failed $(last_line "$LOGDIR/s4.1.log")"
  fi

  timeout 60 nono run --profile "$profile4" -- nix eval --raw nixpkgs#hello.name >"$LOGDIR/s4.2.log" 2>&1
  rc=$?
  if [[ $rc -eq 0 ]]; then
    report S4.2 INFO "nix eval inside nono" "ok"
  else
    report S4.2 INFO "nix eval inside nono" "failed $(last_line "$LOGDIR/s4.2.log")"
  fi

  if [[ "$WITH_PI_USER" -eq 1 ]] && id pi >/dev/null 2>&1; then
    timeout 60 sudo -u pi nono run --profile "$profile4" -- nix build nixpkgs#hello --no-link --option sandbox false >"$LOGDIR/s4.3.log" 2>&1
    rc=$?
    report S4.3 INFO "pi untrusted sandbox=false option" "rc=$rc $(last_line "$LOGDIR/s4.3.log")"

    timeout 60 sudo -u pi nono run --profile "$profile4" -- nix build nixpkgs#hello --no-link --option extra-substituters https://example.invalid >"$LOGDIR/s4.4.log" 2>&1
    rc=$?
    report S4.4 INFO "pi untrusted extra-substituters option" "rc=$rc $(last_line "$LOGDIR/s4.4.log")"

    tu_val="$(timeout 20 nix config show trusted-users 2>"$LOGDIR/s4.5.log")"
    report S4.5 INFO "nix config show trusted-users" "$tu_val"
  else
    report S4.3 SKIP "pi-user checks" "need --with-pi-user and an existing pi user"
  fi
fi

# --- S5: sessions -------------------------------------------------------------

pid_tag="$$"
sess_name="spike-$pid_tag"

out="$(timeout 20 nono run --detached --name "$sess_name" -- sleep 120 2>"$LOGDIR/s5.1.log")"
rc=$?
sess_id="$(printf '%s' "$out" | grep -oE '[0-9a-f-]{8,}' | head -n1)"
if [[ -z "$sess_id" ]]; then
  sess_id="$sess_name"
fi
if [[ $rc -eq 0 ]]; then
  DETACHED_NAMES+=("$sess_name")
  report S5.1 PASS "detached session starts" "id=$sess_id"
else
  report S5.1 FAIL "detached session starts" "rc=$rc $(last_line "$LOGDIR/s5.1.log")"
fi

ps_out="$(timeout 20 nono ps 2>"$LOGDIR/s5.2.log")"
rc=$?
if [[ $rc -eq 0 ]] && printf '%s' "$ps_out" | grep -q "$sess_name"; then
  report S5.2 PASS "nono ps lists session" "ok"
else
  report S5.2 FAIL "nono ps lists session" "rc=$rc $(last_line "$LOGDIR/s5.2.log")"
fi

timeout 20 nono stop "$sess_id" >"$LOGDIR/s5.3.log" 2>&1
stop_rc=$?
ps_out2="$(timeout 20 nono ps 2>>"$LOGDIR/s5.3.log")"
if [[ $stop_rc -eq 0 ]] && ! printf '%s' "$ps_out2" | grep -q "$sess_name"; then
  report S5.3 PASS "nono stop removes session" "ok"
  DETACHED_NAMES=()
else
  report S5.3 FAIL "nono stop removes session" "stop_rc=$stop_rc $(last_line "$LOGDIR/s5.3.log")"
fi

if [[ "$WITH_PI_USER" -eq 1 ]] && id pi >/dev/null 2>&1; then
  pi_sess_name="spike-pi-$pid_tag"
  timeout 20 sudo -u pi nono run --detached --name "$pi_sess_name" -- sleep 120 >"$LOGDIR/s5.4.log" 2>&1
  pi_start_rc=$?
  if [[ $pi_start_rc -eq 0 ]]; then
    ps_as_self="$(timeout 20 nono ps 2>>"$LOGDIR/s5.4.log")"
    shown="not shown"
    if printf '%s' "$ps_as_self" | grep -q "$pi_sess_name"; then
      shown="ok"
    fi

    shared_state="$WORKDIR/shared-xdg-state"
    mkdir -p "$shared_state"
    ps_shared="$(timeout 20 env XDG_STATE_HOME="$shared_state" nono ps 2>>"$LOGDIR/s5.4.log")"
    shared_shown="not shown"
    if printf '%s' "$ps_shared" | grep -q "$pi_sess_name"; then
      shared_shown="ok"
    fi

    report S5.4 INFO "pi-user session cross-visibility" "default=$shown shared-XDG=$shared_shown"
    timeout 20 sudo -u pi nono stop "$pi_sess_name" >>"$LOGDIR/s5.4.log" 2>&1
  else
    report S5.4 INFO "pi-user session cross-visibility" "pi session failed to start rc=$pi_start_rc"
  fi
else
  report S5.4 SKIP "cross-user registry" "need --with-pi-user and an existing pi user"
fi

# --- final block --------------------------------------------------------------

nono_ver="$(timeout 20 nono --version 2>/dev/null | head -n1)"
uname_ver="$(uname -srm)"
nix_ver="$(timeout 20 nix --version 2>/dev/null | head -n1)"

emit "nono $nono_ver"
emit "uname $uname_ver"
emit "nix $nix_ver"
emit "RESULT $PASS_COUNT/$TOTAL_COUNT"

full_output="$(printf '%s\n' "${OUTPUT_LINES[@]}")"
if command -v pbcopy >/dev/null 2>&1; then
  printf '%s' "$full_output" | pbcopy
elif command -v wl-copy >/dev/null 2>&1; then
  printf '%s' "$full_output" | wl-copy
elif command -v xclip >/dev/null 2>&1; then
  printf '%s' "$full_output" | xclip -selection clipboard
fi
