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
    marker="$(mktemp -u)"
    export RUN_SH_MARKER="$marker"
    nix shell github:nolabs-ai/nono#prebuilt nixpkgs#socat nixpkgs#jq nixpkgs#curl nixpkgs#coreutils nixpkgs#nodejs -c bash "$SCRIPT_DIR/run.sh" "$@"
    reexec_rc=$?
    if [[ $reexec_rc -ne 0 && ! -e "$marker" ]]; then
      echo "ERR nono flake ref or nix shell failed"
    fi
    rm -f "$marker"
    exit "$reexec_rc"
  fi
fi

if [[ -n "${RUN_SH_MARKER:-}" ]]; then
  : >"$RUN_SH_MARKER" 2>/dev/null
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

# last3/first3: last/first 3 non-empty lines of a captured stderr log,
# joined by ' | ' and truncated to 200 chars -- used for FAIL/unexpected
# detail only, per the output-size budget.
last3() {
  local target="$1" joined
  if [[ ! -f "$target" ]]; then
    printf ''
    return
  fi
  joined="$(grep -v '^[[:space:]]*$' "$target" | tail -n3 | paste -sd'|' -)"
  joined="${joined//|/ | }"
  printf '%s' "${joined:0:200}"
}

first3() {
  local target="$1" joined
  if [[ ! -f "$target" ]]; then
    printf ''
    return
  fi
  joined="$(grep -v '^[[:space:]]*$' "$target" | head -n3 | paste -sd'|' -)"
  joined="${joined//|/ | }"
  printf '%s' "${joined:0:200}"
}

is_http_ok() {
  [[ "$1" =~ ^[23][0-9][0-9]$ ]]
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

RUNCWD="$WORKDIR/runcwd"
mkdir -p "$RUNCWD"

# nono_run: runs `nono run --allow-cwd ...` from a temp cwd (so nono never
# needs the interactive "share <cwd>?" prompt) with stdin from /dev/null.
nono_run() {
  local secs="$1"
  shift
  (cd "$RUNCWD" && timeout "$secs" nono run --allow-cwd "$@" </dev/null)
}

nono_run_pi() {
  local secs="$1"
  shift
  (cd "$RUNCWD" && timeout "$secs" sudo -u pi nono run --allow-cwd "$@" </dev/null)
}

gen_profile() {
  local out="$1" port="$2" token="$3"
  sed -e "s#__PORT__#$port#" -e "s#__TOKEN__#$token#" "$SCRIPT_DIR/approval.template.json" >"$out"
}

# --- S1: network approval ---------------------------------------------------

SPIKE_TOKEN="$(head -c16 /dev/urandom | od -An -tx1 | tr -d ' \n')"
export SPIKE_TOKEN
export SPIKE_LOG="$WORKDIR/requests.log"
: >"$SPIKE_LOG"

HANDLER="$SCRIPT_DIR/handler.sh"
chmod +x "$HANDLER" 2>/dev/null

port_is_closed() {
  ! timeout 1 bash -c "exec 3<>/dev/tcp/127.0.0.1/$1" 2>/dev/null
}

PORT=""
SOCAT_PID=""
for _ in 1 2 3 4 5; do
  candidate="$(shuf -i 20000-60000 -n1)"
  port_is_closed "$candidate" || continue
  : >"$LOGDIR/socat.log"
  timeout 65 socat TCP-LISTEN:"$candidate",bind=127.0.0.1,reuseaddr,fork EXEC:"bash $HANDLER" >"$LOGDIR/socat.log" 2>&1 &
  SOCAT_PID=$!
  sleep 0.5
  if kill -0 "$SOCAT_PID" 2>/dev/null; then
    PORT="$candidate"
    break
  fi
  wait "$SOCAT_PID" 2>/dev/null
  SOCAT_PID=""
done
if [[ -z "$PORT" ]]; then
  report S1.0 ERR "webhook listener bind" "failed to bind after 5 attempts"
fi

PROFDIR="$WORKDIR/profiles"
mkdir -p "$PROFDIR"

PROFILE1="$PROFDIR/s1.json"
gen_profile "$PROFILE1" "$PORT" "$SPIKE_TOKEN"

timeout 60 nono profile validate "$PROFILE1" >"$LOGDIR/s1.1.log" 2>&1
rc=$?
if [[ $rc -eq 0 ]]; then
  report S1.1 PASS "nono profile validate" "ok"
else
  report S1.1 FAIL "nono profile validate" "$(last3 "$LOGDIR/s1.1.log")" 200
fi

code="$(nono_run 60 --profile "$PROFILE1" -- curl -sS --max-time 20 -o /dev/null -w '%{http_code}' https://example.com 2>"$LOGDIR/s1.2.log")"
if is_http_ok "$code" && grep -q '"host":"example.com"' "$SPIKE_LOG" 2>/dev/null; then
  report S1.2 PASS "curl example.com granted" "code=$code"
else
  report S1.2 FAIL "curl example.com granted" "code=$code $(last3 "$LOGDIR/s1.2.log")" 200
fi

code="$(nono_run 60 --profile "$PROFILE1" -- curl -sS --max-time 20 -o /dev/null -w '%{http_code}' https://example.org 2>"$LOGDIR/s1.3.log")"
if ! is_http_ok "$code" && grep -q '"host":"example.org"' "$SPIKE_LOG" 2>/dev/null; then
  report S1.3 PASS "curl example.org denied" "code=$code"
else
  report S1.3 FAIL "curl example.org denied" "code=$code $(last3 "$LOGDIR/s1.3.log")" 200
fi

out="$(nono_run 60 --profile "$PROFILE1" -- sh -c 'curl -s -o /dev/null -w "%{http_code} " https://httpbin.org/status/200 && curl -s -o /dev/null -w "%{http_code}" https://httpbin.org/status/200' 2>"$LOGDIR/s1.4.log")"
count="$(grep -c '"host":"httpbin.org"' "$SPIKE_LOG" 2>/dev/null)"
code1="${out%% *}"
code2="${out##* }"
if [[ "$code1" == 5* || "$code2" == 5* ]]; then
  report S1.4 INFO "two httpbin calls, single ask" "httpbin 5xx: out=$out count=$count"
elif is_http_ok "$code1" && is_http_ok "$code2" && [[ "$count" -eq 1 ]]; then
  report S1.4 PASS "two httpbin calls, single ask" "count=$count out=$out"
else
  report S1.4 FAIL "two httpbin calls, single ask" "count=$count out=$out $(last3 "$LOGDIR/s1.4.log")" 200
fi

code="$(nono_run 60 --profile "$PROFILE1" -- curl --noproxy '*' -sS --max-time 20 -o /dev/null -w '%{http_code}' https://example.com 2>"$LOGDIR/s1.5.log")"
if ! is_http_ok "$code"; then
  report S1.5 PASS "curl bypassing proxy fails" "code=$code"
else
  report S1.5 FAIL "curl bypassing proxy fails" "code=$code $(last3 "$LOGDIR/s1.5.log")" 200
fi

before_count="$(wc -l <"$SPIKE_LOG")"
code="$(nono_run 60 --profile "$PROFILE1" -- curl -sS --max-time 20 -o /dev/null -w '%{http_code}' http://169.254.169.254/ 2>"$LOGDIR/s1.6.log")"
after_count="$(wc -l <"$SPIKE_LOG")"
if ! is_http_ok "$code" && [[ "$after_count" -eq "$before_count" ]]; then
  report S1.6 PASS "metadata IP blocked, not asked" "code=$code"
else
  report S1.6 FAIL "metadata IP blocked, not asked" "code=$code before=$before_count after=$after_count $(last3 "$LOGDIR/s1.6.log")" 200
fi

port_url="http://127.0.0.1:${PORT}/${SPIKE_TOKEN}"
before_count="$(wc -l <"$SPIKE_LOG")"
helper_code1="$(nono_run 60 --profile "$PROFILE1" -- curl --noproxy '*' -m 5 -sS -o /dev/null -w '%{http_code}' "$port_url" 2>"$LOGDIR/s1.7a.log")"
helper_code2="$(nono_run 60 --profile "$PROFILE1" -- curl -m 5 -sS -o /dev/null -w '%{http_code}' "$port_url" 2>"$LOGDIR/s1.7b.log")"
after_count="$(wc -l <"$SPIKE_LOG")"
if ! is_http_ok "$helper_code1" && ! is_http_ok "$helper_code2" && [[ "$after_count" -eq "$before_count" ]]; then
  report S1.7 PASS "sandboxed child cannot reach helper" "direct=$helper_code1 proxied=$helper_code2"
else
  report S1.7 FAIL "sandboxed child cannot reach helper" "direct=$helper_code1 proxied=$helper_code2 before=$before_count after=$after_count $(last3 "$LOGDIR/s1.7b.log")" 200
fi

BAD_PORT=""
for _ in 1 2 3; do
  candidate="$(shuf -i 20000-60000 -n1)"
  if [[ "$candidate" != "$PORT" ]] && port_is_closed "$candidate"; then
    BAD_PORT="$candidate"
    break
  fi
done
if [[ -z "$BAD_PORT" ]]; then
  BAD_PORT=$((PORT + 1))
fi
PROFILE1B="$PROFDIR/s1-badport.json"
gen_profile "$PROFILE1B" "$BAD_PORT" "$SPIKE_TOKEN"
code="$(nono_run 60 --profile "$PROFILE1B" -- curl -sS --max-time 20 -o /dev/null -w '%{http_code}' https://example.com 2>"$LOGDIR/s1.8.log")"
if ! is_http_ok "$code"; then
  report S1.8 PASS "fail-closed on unreachable webhook" "code=$code"
else
  report S1.8 FAIL "fail-closed on unreachable webhook" "code=$code $(last3 "$LOGDIR/s1.8.log")" 200
fi

first_line="$(head -n1 "$SPIKE_LOG" 2>/dev/null)"
first_compact="$(printf '%s' "$first_line" | jq -c . 2>/dev/null)"
if [[ -z "$first_compact" ]]; then
  first_compact="$first_line"
fi
report S1.9 INFO "first request body" "$first_compact" 300

# --- S2: pi-like runtime under the proxy ------------------------------------

nono_run 60 --profile "$PROFILE1" -- getent hosts example.com >"$LOGDIR/s2.1.log" 2>&1
rc=$?
report S2.1 INFO "getent hosts example.com" "rc=$rc $(last_line "$LOGDIR/s2.1.log")"

nono_run 60 --profile "$PROFILE1" -- getent hosts example.net >"$LOGDIR/s2.2.log" 2>&1
rc=$?
report S2.2 INFO "getent hosts example.net" "rc=$rc $(last_line "$LOGDIR/s2.2.log")"

NODE_FETCH_JS='fetch("https://example.com").then(function(r){console.log(r.status);process.exit(r.ok?0:1)}).catch(function(e){console.error(String(e));process.exit(1)})'

out="$(nono_run 60 --profile "$PROFILE1" -- env NODE_USE_ENV_PROXY=1 node -e "$NODE_FETCH_JS" 2>"$LOGDIR/s2.3.log")"
rc=$?
status_line="$(printf '%s' "$out" | tail -n1)"
if [[ $rc -eq 0 ]] && [[ "$status_line" =~ ^[23][0-9][0-9]$ ]]; then
  report S2.3 PASS "node fetch w/ NODE_USE_ENV_PROXY" "status=$status_line"
else
  report S2.3 FAIL "node fetch w/ NODE_USE_ENV_PROXY" "rc=$rc out=$status_line $(last3 "$LOGDIR/s2.3.log")" 200
fi

out2="$(nono_run 60 --profile "$PROFILE1" -- node -e "$NODE_FETCH_JS" 2>"$LOGDIR/s2.4.log")"
rc2=$?
report S2.4 INFO "node fetch without env proxy" "rc=$rc2 out=$(printf '%s' "$out2" | tail -n1) $(last_line "$LOGDIR/s2.4.log")"

if command -v pi >/dev/null 2>&1; then
  nono_run 60 --profile "$PROFILE1" -- pi --version >"$LOGDIR/s2.5.log" 2>&1
  rc=$?
  report S2.5 INFO "pi --version inside nono" "rc=$rc $(last_line "$LOGDIR/s2.5.log")"
else
  report S2.5 SKIP "pi --version inside nono" "pi not on PATH"
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

nono_run 60 --profile "$PROFILE3A" -- cat "$FSDIR/secret.txt" >"$LOGDIR/s3.1.secret.log" 2>&1
secret_rc=$?
nono_run 60 --profile "$PROFILE3A" -- cat "$FSDIR/ok.txt" >"$LOGDIR/s3.1.ok.log" 2>&1
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
  local target="$1" bin="$2" real
  if [[ -n "$bin" ]]; then
    real="$(readlink -f "$bin" 2>/dev/null)"
    if [[ -n "$real" && -e "$real" ]]; then
      timeout 60 nix-store -qR "$real" >>"$target" 2>>"$LOGDIR/closure.err"
    fi
  fi
}

add_closure "$base_closure_file" "$(command -v true)"
add_closure "$base_closure_file" "$(command -v echo)"
add_closure "$base_closure_file" "$(command -v bash)"
add_closure "$base_closure_file" "$(command -v curl)"
sort -u "$base_closure_file" -o "$base_closure_file"
base_size="$(wc -l <"$base_closure_file")"

closure_file="$WORKDIR/closure_full.txt"
cp "$base_closure_file" "$closure_file"

pad_sources=()
if command -v nix >/dev/null 2>&1; then
  nix_real="$(readlink -f "$(command -v nix)" 2>/dev/null)"
  if [[ -n "$nix_real" ]]; then
    pad_sources+=("$nix_real")
  fi
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
  timeout 60 nix-store -qR "$src" >>"$closure_file" 2>>"$LOGDIR/closure.err"
  sort -u "$closure_file" -o "$closure_file"
done

total_closure="$(wc -l <"$closure_file")"
true_bin="$(command -v true)"

reads_json="$(jq -R -s -c 'split("\n") | map(select(length > 0))' "$base_closure_file")"
profile_ctrl="$PROFDIR/s3-closure-ctrl.json"
jq -n --argjson reads "$reads_json" '{
  "extends": "default",
  "meta": {"name": "spike-s3-closure-ctrl"},
  "groups": {"include": []},
  "workdir": {"access": "none"},
  "filesystem": {"allow": [], "read": $reads, "deny": [], "unix_socket": []}
}' >"$profile_ctrl"

nono_run 60 --profile "$profile_ctrl" -- "$true_bin" >"$LOGDIR/s3.2.ctrl.log" 2>&1
ctrl_rc=$?
if [[ $ctrl_rc -eq 0 ]]; then
  report S3.2 INFO "control N=$base_size" "ok"
else
  report S3.2 ERR "control failed" "$(last3 "$LOGDIR/s3.2.ctrl.log")" 200
fi

if [[ $ctrl_rc -eq 0 ]]; then
  for n in 1000 2000 5000 10000; do
    if [[ "$n" -le "$base_size" || "$n" -gt "$total_closure" ]]; then
      continue
    fi
    subset_file="$WORKDIR/closure_$n.txt"
    head -n "$n" "$closure_file" >"$subset_file"
    n_reads_json="$(jq -R -s -c 'split("\n") | map(select(length > 0))' "$subset_file")"
    profile_n="$PROFDIR/s3-closure-$n.json"
    jq -n --argjson reads "$n_reads_json" '{
      "extends": "default",
      "meta": {"name": "spike-s3-closure"},
      "groups": {"include": []},
      "workdir": {"access": "none"},
      "filesystem": {"allow": [], "read": $reads, "deny": [], "unix_socket": []}
    }' >"$profile_n"

    start_ts="$(date +%s)"
    nono_run 60 --profile "$profile_n" -- "$true_bin" >"$LOGDIR/s3.2.$n.log" 2>&1
    rc=$?
    end_ts="$(date +%s)"
    elapsed=$((end_ts - start_ts))
    if [[ $rc -eq 0 ]]; then
      report S3.2 INFO "closure N=$n" "ok, ${elapsed}s"
    else
      report S3.2 INFO "closure N=$n" "failed, ${elapsed}s $(last3 "$LOGDIR/s3.2.$n.log")" 200
      break
    fi
  done
fi

hello_path="$(timeout 60 nix build nixpkgs#hello --no-link --print-out-paths 2>"$LOGDIR/s3.3.build.log")"
build_rc=$?
if [[ $build_rc -ne 0 || -z "$hello_path" || ! -x "$hello_path/bin/hello" ]]; then
  report S3.3 SKIP "no hello" "$(last3 "$LOGDIR/s3.3.build.log")" 200
  report S3.4 SKIP "no hello" "skipped, see S3.3"
  report S3.5 SKIP "no hello" "skipped, see S3.3"
else
  hello_bin="$hello_path/bin/hello"

  nono_run 60 --profile "$profile_ctrl" -- "$hello_bin" >"$LOGDIR/s3.3.hello.log" 2>&1
  hello_rc=$?
  stderr_hit="no"
  if grep -Eqi 'permission denied|not permitted' "$LOGDIR/s3.3.hello.log" 2>/dev/null; then
    stderr_hit="yes"
  fi
  if [[ $hello_rc -eq 126 || "$stderr_hit" == "yes" ]]; then
    report S3.3 PASS "hello outside closure denied" "rc=$hello_rc"
  elif [[ $hello_rc -eq 127 ]]; then
    report S3.3 ERR "hello outside closure denied" "rc=127 not found $(last3 "$LOGDIR/s3.3.hello.log")" 200
  elif [[ $hello_rc -eq 0 ]]; then
    report S3.3 FAIL "hello outside closure denied" "ran successfully, rc=0"
  else
    report S3.3 FAIL "hello outside closure denied" "rc=$hello_rc $(last3 "$LOGDIR/s3.3.hello.log")" 200
  fi

  echo_bin="$(command -v echo)"
  nono_run 60 --profile "$profile_ctrl" -- "$echo_bin" hi >"$LOGDIR/s3.4.echo.log" 2>&1
  echo_rc=$?
  if [[ $echo_rc -eq 0 ]]; then
    report S3.4 PASS "coreutils echo inside closure" "rc=0"
  else
    report S3.4 FAIL "coreutils echo inside closure" "rc=$echo_rc $(last3 "$LOGDIR/s3.4.echo.log")" 200
  fi

  hello_closure_file="$WORKDIR/hello_closure.txt"
  timeout 60 nix-store -qR "$hello_path" >"$hello_closure_file" 2>>"$LOGDIR/closure.err"
  cat "$base_closure_file" >>"$hello_closure_file"
  sort -u "$hello_closure_file" -o "$hello_closure_file"
  hello_reads_json="$(jq -R -s -c 'split("\n") | map(select(length > 0))' "$hello_closure_file")"
  profile3d="$PROFDIR/s3-read-exec.json"
  jq -n --argjson reads "$hello_reads_json" --arg hello "$hello_bin" '{
    "extends": "default",
    "meta": {"name": "spike-s3-read-exec"},
    "groups": {"include": []},
    "workdir": {"access": "none"},
    "filesystem": {"allow": [], "read": $reads, "read_file": [$hello], "deny": [], "unix_socket": []}
  }' >"$profile3d"
  nono_run 60 --profile "$profile3d" -- "$hello_bin" >"$LOGDIR/s3.5.log" 2>&1
  rc=$?
  if [[ $rc -eq 0 ]]; then
    report S3.5 INFO "read-implies-exec" "runs"
  else
    report S3.5 INFO "read-implies-exec" "blocked, rc=$rc $(last3 "$LOGDIR/s3.5.log")" 200
  fi
fi

# --- S4: nix daemon inside nono ----------------------------------------------

DAEMON_SOCK="/nix/var/nix/daemon-socket/socket"
if [[ ! -e "$DAEMON_SOCK" ]]; then
  report S4 SKIP "nix daemon inside nono" "socket not found at $DAEMON_SOCK"
else
  HOMEDIR="$WORKDIR/home"
  mkdir -p "$HOMEDIR/.cache"
  chmod -R 0777 "$HOMEDIR" 2>/dev/null

  profile4="$PROFDIR/s4-daemon.json"
  jq -n --arg sock "$DAEMON_SOCK" --arg home "$HOMEDIR" '{
    "extends": "default",
    "meta": {"name": "spike-s4-nix-daemon"},
    "groups": {"include": []},
    "workdir": {"access": "none"},
    "filesystem": {"read": ["/nix/store"], "allow": [$home], "deny": [], "unix_socket": [$sock]}
  }' >"$profile4"

  SPIKE_BASH="$(command -v bash)"
  export SPIKE_BASH
  # $out must stay literal; it is expanded by the derivation's builder
  # shell at build time, not by this script.
  # shellcheck disable=SC2016
  drv_expr='derivation { name = "spike"; system = builtins.currentSystem; builder = builtins.getEnv "SPIKE_BASH"; args = [ "-c" "echo ok > $out" ]; }'

  nono_run 60 --profile "$profile4" -- env HOME="$HOMEDIR" XDG_CACHE_HOME="$HOMEDIR/.cache" NIX_REMOTE=daemon SPIKE_BASH="$SPIKE_BASH" nix --extra-experimental-features 'nix-command flakes' store info --store daemon >"$LOGDIR/s4.1.log" 2>&1
  rc=$?
  if [[ $rc -eq 0 ]]; then
    report S4.1 INFO "nix store info --store daemon" "ok"
  else
    report S4.1 INFO "nix store info --store daemon" "failed $(last_line "$LOGDIR/s4.1.log")"
  fi

  nono_run 60 --profile "$profile4" -- env HOME="$HOMEDIR" XDG_CACHE_HOME="$HOMEDIR/.cache" NIX_REMOTE=daemon SPIKE_BASH="$SPIKE_BASH" nix --extra-experimental-features 'nix-command flakes' eval --expr '1+1' >"$LOGDIR/s4.2.log" 2>&1
  rc=$?
  if [[ $rc -eq 0 ]]; then
    report S4.2 INFO "nix eval --expr 1+1" "ok"
  else
    report S4.2 INFO "nix eval --expr 1+1" "failed $(last_line "$LOGDIR/s4.2.log")"
  fi

  bash_store_path="$(readlink -f "$(command -v bash)")"
  nono_run 60 --profile "$profile4" -- env HOME="$HOMEDIR" XDG_CACHE_HOME="$HOMEDIR/.cache" NIX_REMOTE=daemon SPIKE_BASH="$SPIKE_BASH" nix --extra-experimental-features 'nix-command flakes' path-info --store daemon "$bash_store_path" >"$LOGDIR/s4.3.log" 2>&1
  rc=$?
  if [[ $rc -eq 0 ]]; then
    report S4.3 INFO "nix path-info bash" "ok"
  else
    report S4.3 INFO "nix path-info bash" "failed $(last_line "$LOGDIR/s4.3.log")"
  fi

  nono_run 60 --profile "$profile4" -- env HOME="$HOMEDIR" XDG_CACHE_HOME="$HOMEDIR/.cache" NIX_REMOTE=daemon SPIKE_BASH="$SPIKE_BASH" nix --extra-experimental-features 'nix-command flakes' build --no-link "$bash_store_path" >"$LOGDIR/s4.4.log" 2>&1
  rc=$?
  if [[ $rc -eq 0 ]]; then
    report S4.4 INFO "nix build existing path" "ok"
  else
    report S4.4 INFO "nix build existing path" "failed $(last_line "$LOGDIR/s4.4.log")"
  fi

  nono_run 60 --profile "$profile4" -- env HOME="$HOMEDIR" XDG_CACHE_HOME="$HOMEDIR/.cache" NIX_REMOTE=daemon SPIKE_BASH="$SPIKE_BASH" nix --extra-experimental-features 'nix-command flakes' build --impure --no-link --expr "$drv_expr" >"$LOGDIR/s4.5.log" 2>&1
  rc=$?
  if [[ $rc -eq 0 ]]; then
    report S4.5 INFO "trivial derivation build" "ok"
  else
    report S4.5 INFO "trivial derivation build" "failed $(last_line "$LOGDIR/s4.5.log")"
  fi

  if [[ "$WITH_PI_USER" -eq 1 ]] && id pi >/dev/null 2>&1; then
    nono_run_pi 60 --profile "$profile4" -- env HOME="$HOMEDIR" XDG_CACHE_HOME="$HOMEDIR/.cache" NIX_REMOTE=daemon SPIKE_BASH="$SPIKE_BASH" nix --extra-experimental-features nix-command build --impure --no-link --option sandbox false --expr "$drv_expr" >"$LOGDIR/s4.6.log" 2>&1
    rc=$?
    report S4.6 INFO "pi untrusted sandbox=false option" "$([[ $rc -eq 0 ]] && echo ok || echo failed) $(last_line "$LOGDIR/s4.6.log")"

    nono_run_pi 60 --profile "$profile4" -- env HOME="$HOMEDIR" XDG_CACHE_HOME="$HOMEDIR/.cache" NIX_REMOTE=daemon SPIKE_BASH="$SPIKE_BASH" nix --extra-experimental-features nix-command build --impure --no-link --option extra-substituters https://example.invalid --expr "$drv_expr" >"$LOGDIR/s4.7.log" 2>&1
    rc=$?
    report S4.7 INFO "pi untrusted extra-substituters option" "$([[ $rc -eq 0 ]] && echo ok || echo failed) $(last_line "$LOGDIR/s4.7.log")"

    tu_val="$(timeout 20 nix config show trusted-users 2>"$LOGDIR/s4.8.log")"
    report S4.8 INFO "nix config show trusted-users" "$tu_val"
  else
    report S4.6 SKIP "pi-user checks" "need --with-pi-user and an existing pi user"
  fi
fi

# --- S5: sessions -------------------------------------------------------------

pid_tag="$$"
sess_name="spike-$pid_tag"

out="$(nono_run 20 --detached --name "$sess_name" -- sleep 120 2>"$LOGDIR/s5.1.log")"
rc=$?
sess_id="$(printf '%s' "$out" | grep -oE '[0-9a-f-]{8,}' | head -n1)"
if [[ -z "$sess_id" ]]; then
  sess_id="$sess_name"
fi
if [[ $rc -eq 0 ]]; then
  DETACHED_NAMES+=("$sess_name")
  report S5.1 PASS "detached session starts" "id=$sess_id"
else
  report S5.1 FAIL "detached session starts" "rc=$rc $(first3 "$LOGDIR/s5.1.log")" 200
fi

ps_out="$(timeout 20 nono ps 2>"$LOGDIR/s5.2.log")"
rc=$?
if [[ $rc -eq 0 ]] && printf '%s' "$ps_out" | grep -q "$sess_name"; then
  report S5.2 PASS "nono ps lists session" "ok"
else
  report S5.2 FAIL "nono ps lists session" "rc=$rc $(last3 "$LOGDIR/s5.2.log")" 200
fi

timeout 20 nono stop "$sess_id" >"$LOGDIR/s5.3.log" 2>&1
stop_rc=$?
ps_out2="$(timeout 20 nono ps 2>>"$LOGDIR/s5.3.log")"
if [[ $stop_rc -eq 0 ]] && ! printf '%s' "$ps_out2" | grep -q "$sess_name"; then
  report S5.3 PASS "nono stop removes session" "ok"
  DETACHED_NAMES=()
else
  report S5.3 FAIL "nono stop removes session" "stop_rc=$stop_rc $(last3 "$LOGDIR/s5.3.log")" 200
fi

if [[ "$WITH_PI_USER" -eq 1 ]] && id pi >/dev/null 2>&1; then
  pi_sess_name="spike-pi-$pid_tag"
  nono_run_pi 20 --detached --name "$pi_sess_name" -- sleep 120 >"$LOGDIR/s5.4.log" 2>&1
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
    report S5.4 INFO "pi-user session cross-visibility" "pi session failed to start, rc=$pi_start_rc $(last3 "$LOGDIR/s5.4.log")" 200
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
  printf '%s' "$full_output" | pbcopy >/dev/null 2>&1 || true
elif [[ -n "${WAYLAND_DISPLAY:-}" ]] && command -v wl-copy >/dev/null 2>&1; then
  printf '%s' "$full_output" | wl-copy >/dev/null 2>&1 || true
elif [[ -n "${DISPLAY:-}" ]] && command -v xclip >/dev/null 2>&1; then
  printf '%s' "$full_output" | xclip -selection clipboard >/dev/null 2>&1 || true
fi
