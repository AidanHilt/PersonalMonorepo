#!/usr/bin/env bash
# nix run $PERSONAL_MONOREPO_LOCATION/nix/agentic-ai-stack-nono#start-agent
#
# Rewritten for Phase 4a of PLAN.md: no more docker/compose/kind. Brings up
# one nono-sandboxed `pi` session as the untrusted `pi` user (see PLAN.md's
# "Isolation user" decision row and nix/mono-flake's `_pi-user-linux.nix`/
# `_pi-user-darwin.nix` for the NOPASSWD+SETENV sudo rule this relies on).
#
# High-level flow (see IMPLEMENTERS.md's "Launcher and approval helper
# (Phase 4a)" section for the full writeup and the judgement calls below):
#   1. Seed/refresh a per-run, `pi`-owned state tree under
#      /var/lib/pi/runs/<name>/ (fresh PI_CODING_AGENT_DIR, a pi-owned copy
#      of the workdir + any --add/--clone extras). This is "idempotent":
#      re-running with the SAME --name merges fresh config/extensions/
#      skills on top WITHOUT deleting anything `pi` itself wrote there
#      (session history, scratch files) -- that's what lets `--resume`
#      mean anything across repeated launches.
#   2. Start the host-side approval helper (outside the sandbox), and read
#      back its webhook URL.
#   3. Generate the launch-ready nono profile (scripts/gen-profile.sh).
#   4. Run `nono run` as `pi` via sudo, with the per-run dir as `pi`'s cwd
#      (nono's "workdir").
#
# `pi` never gets a bind-mounted view of the invoking user's own files --
# per PLAN.md's "Sharing files between aidan and pi" decision row, it works
# inside a `pi`-owned COPY, and getting results back out is on the user
# (inspect/diff/rsync the per-run workdir copy manually -- this launcher
# does not automate that, unlike the `agent-stage` flow IMPLEMENT
# subagents use, which is unrelated machinery for a different workflow).
#
# Every write under /var/lib/pi goes through a `sudo -u pi` invocation
# (mkdir/tee/tar -x/cp); every READ of the invoking user's own files (the
# workdir, --add/--clone sources, config/agent/) runs as the invoking
# user. That split is what lets this work without the invoking user ever
# needing traversal rights into pi-owned directories, and without `pi`
# ever needing read access into the invoking user's home directory.
set -euo pipefail

# --- PERSONAL_MONOREPO_LOCATION: same precedent as the container-era script
# ---------------------------------------------------------------------------
# gen-profile.sh, profiles/work.base.json, and config/agent/ are all read
# directly from the checkout (not re-packaged into the Nix store the way
# this script itself is, via flake.nix's writeShellApplication) -- same
# convention the container-era script already relied on for
# `nix/agentic-ai-stack`. gen-profile.sh and work.base.json are read
# directly off disk by this script (running as the invoking user), so no
# `pi`-readability is needed for those two. config/agent/ is instead
# streamed in via a tar pipe (see tar_copy_to_pi below), so it doesn't need
# to be `pi`-readable in place either.
: "${PERSONAL_MONOREPO_LOCATION:?PERSONAL_MONOREPO_LOCATION must point at the monorepo checkout}"
STACK_DIR="$PERSONAL_MONOREPO_LOCATION/nix/agentic-ai-stack-nono"
GEN_PROFILE_SH="$STACK_DIR/scripts/gen-profile.sh"
BASE_PROFILE="$STACK_DIR/profiles/work.base.json"
CONFIG_AGENT_DIR="$STACK_DIR/config/agent"
CONFIG_WEB_SEARCH="$STACK_DIR/config/web-search.json"

RUNS_ROOT="/var/lib/pi/runs"

PROFILE_FLAG="work"
AUDIT_FLAG=0
DETACHED_FLAG=0
NAME_FLAG=""
RESUME_FLAG=0
DRY_RUN=0
ADD_PATHS=()
CLONE_PATHS=()
SECRET_ARGS=() # "NAME=VALUE" pairs from --secret, applied after the namespace scan

print_help() {
  cat <<'EOF'
Usage: start-agent.sh [FLAGS]

Starts one nono-sandboxed `pi` session as the untrusted `pi` user (nix run
.#start-agent). See IMPLEMENTERS.md's "Launcher and approval helper
(Phase 4a)" section for the full architecture writeup.

Flags:
  --profile work            Which flake-owned nono profile to use. "work"
                             is the only value in the MVP (required to be
                             spelled out, to leave room for a future debug
                             profile -- see PLAN.md section 5).
  --audit                    Pass `--audit-integrity` to `nono run`.
  --detached                 Pass `--detached` to `nono run`: the session
                             (and its approval helper) outlive this
                             launcher process -- see "Detached sessions"
                             below. Use the (future, Phase 4b) `attach`/
                             `ps`/`stop` wrappers to interact with it.
  --add PATH                 An existing host file or directory, copied
                             (not bind-mounted) into a pi-owned location
                             and granted read-write (repeatable).
  --clone URL                A URL cloned on the HOST (so host git
                             credentials/ssh-agent are used, not anything
                             inside the sandbox) and then handled exactly
                             like --add (repeatable).
  --secret NAME=VALUE        Inject an already-decrypted secret as an env
                             var into the `pi` process (repeatable). Never
                             appears in argv/`ps` -- see "Secrets" below.
  --name NAME                Session name (nono's own `--name`), and the
                             per-run state directory name
                             (/var/lib/pi/runs/NAME/). Default: "pi"
                             (deliberately NOT timestamp-suffixed -- see
                             "Idempotent per-run seeding / --resume"
                             below).
  --resume                   Forwarded to `pi` itself as `--resume` (pi's
                             own session picker) -- unrelated to nono's own
                             session concept. Mutually exclusive with
                             --name (matches the old container-era
                             semantics).
  --dry-run                  Print the resolved `nono run` command (secret
                             VALUES redacted, names shown) and exit. No
                             directories are created, no approval helper is
                             started, no sudo/nono/tar commands run.
  --help, -h                 Show this help and exit.

Environment variables:
  PI_SANDBOX__SECRET__<NAME>  Same as --secret NAME=VALUE (scanned first;
                               a --secret flag with the same NAME wins).
  PERSONAL_MONOREPO_LOCATION   Path to the monorepo checkout (required).

Idempotent per-run seeding / --resume:
  Every launch re-syncs /var/lib/pi/runs/<name>/pi/agent/ from
  config/agent/ plus the pi-extra-extensions/pi-extra-skills build
  outputs -- but it only ever ADDS/overwrites those specific files, never
  deletes the run directory first. Re-running with the SAME --name reuses
  the same pi-owned workdir copy and the same PI_CODING_AGENT_DIR tree, so
  anything `pi` itself persists there (its own session history, included)
  survives across launches -- that's what makes --resume meaningful here.
  A fresh --name starts from a clean copy of the current workdir.

Detached sessions:
  --detached starts a small supervisor (its own session, via `setsid`,
  logging to /var/lib/pi/runs/<name>/supervisor.log) that outlives this
  launcher process: it starts the approval helper, runs
  `nono run --detached`, then polls `nono ps` until the session is gone,
  at which point it stops the approval helper and exits. This launcher
  process itself returns immediately once the detached session has
  started.

See README.md and IMPLEMENTERS.md for the full writeup.
EOF
}

resolve_or_die() {
  local name="$1" path
  if ! path="$(command -v "$name" 2>/dev/null)"; then
    echo "error: required tool not found on PATH: $name" >&2
    exit 1
  fi
  readlink -f "$path"
}

add_extra() {
  local kind="$1" value="$2"
  if [ "$kind" = add ]; then ADD_PATHS+=("$value"); else CLONE_PATHS+=("$value"); fi
}

handle_add() {
  local p="${1:?--add requires a PATH argument}"
  if [ ! -e "$p" ]; then
    echo "error: --add path does not exist: $p" >&2
    exit 1
  fi
  add_extra add "$(realpath "$p")"
}

handle_clone() {
  local url="${1:?--clone requires a URL argument}" repo_name clones_dir dest
  repo_name="$(basename "$url")"
  repo_name="${repo_name%.git}"
  if [ -z "$repo_name" ]; then
    echo "error: --clone could not derive a repo name from URL: $url" >&2
    exit 1
  fi
  clones_dir="${XDG_CACHE_HOME:-$HOME/.cache}/pi-sandbox/clones"
  mkdir -p "$clones_dir"
  dest="$clones_dir/$repo_name"
  if [ -d "$dest/.git" ]; then
    echo "==> --clone: $repo_name already cloned at $dest -- fetching only." >&2
    git -C "$dest" fetch
  else
    echo "==> --clone: cloning $url into $dest..." >&2
    git clone "$url" "$dest"
  fi
  add_extra clone "$dest"
}

while [ $# -gt 0 ]; do
  case "$1" in
  --help | -h)
    print_help
    exit 0
    ;;
  --profile)
    PROFILE_FLAG="${2:?--profile requires an argument}"
    shift 2
    ;;
  --profile=*)
    PROFILE_FLAG="${1#--profile=}"
    shift
    ;;
  --audit)
    AUDIT_FLAG=1
    shift
    ;;
  --detached)
    DETACHED_FLAG=1
    shift
    ;;
  --name)
    NAME_FLAG="${2:?--name requires a NAME argument}"
    shift 2
    ;;
  --name=*)
    NAME_FLAG="${1#--name=}"
    shift
    ;;
  --resume)
    RESUME_FLAG=1
    shift
    ;;
  --dry-run)
    DRY_RUN=1
    shift
    ;;
  --add)
    handle_add "${2:?--add requires a PATH argument}"
    shift 2
    ;;
  --add=*)
    handle_add "${1#--add=}"
    shift
    ;;
  --clone)
    handle_clone "${2:?--clone requires a URL argument}"
    shift 2
    ;;
  --clone=*)
    handle_clone "${1#--clone=}"
    shift
    ;;
  --secret)
    secret_arg="${2:?--secret requires a NAME=VALUE argument}"
    secret_name="${secret_arg%%=*}"
    if [ -z "$secret_name" ] || [ "$secret_arg" = "${secret_arg#*=}" ]; then
      echo "error: --secret requires a NAME=VALUE argument with a non-empty NAME (got: $secret_arg)" >&2
      exit 1
    fi
    SECRET_ARGS+=("$secret_arg")
    shift 2
    ;;
  --secret=*)
    secret_arg="${1#--secret=}"
    secret_name="${secret_arg%%=*}"
    if [ -z "$secret_name" ] || [ "$secret_arg" = "${secret_arg#*=}" ]; then
      echo "error: --secret requires a NAME=VALUE argument with a non-empty NAME (got: $secret_arg)" >&2
      exit 1
    fi
    SECRET_ARGS+=("$secret_arg")
    shift
    ;;
  *)
    echo "error: unrecognized argument: $1" >&2
    exit 1
    ;;
  esac
done

if [ "$PROFILE_FLAG" != "work" ]; then
  echo "error: --profile only supports 'work' in this MVP (got: $PROFILE_FLAG)" >&2
  exit 1
fi
if [ "$RESUME_FLAG" = "1" ] && [ -n "$NAME_FLAG" ]; then
  echo "error: --resume and --name are mutually exclusive." >&2
  exit 1
fi

SESSION_NAME="${NAME_FLAG:-pi}"
echo "==> Session name: $SESSION_NAME" >&2

# --- Secrets: namespace scan first, then --secret flags (flags win) -------
# Collected as real exported env vars on THIS process (never as `-e`/argv
# tokens anywhere), then threaded through `sudo --preserve-env=<names>`
# below -- per PLAN.md's "Secrets" decision row: "never via argv, since
# that is visible via ps".
SECRET_NAMES=()
while IFS= read -r var_name; do
  [ -n "$var_name" ] || continue
  secret_name="${var_name#PI_SANDBOX__SECRET__}"
  export "$secret_name=${!var_name}"
  SECRET_NAMES+=("$secret_name")
done < <(compgen -v PI_SANDBOX__SECRET__ || true)

for secret_arg in "${SECRET_ARGS[@]:-}"; do
  [ -n "$secret_arg" ] || continue
  secret_name="${secret_arg%%=*}"
  secret_value="${secret_arg#*=}"
  export "$secret_name=$secret_value"
  SECRET_NAMES+=("$secret_name")
done

PRESERVE_LIST="PI_CODING_AGENT_DIR,XDG_STATE_HOME"
for secret_name in "${SECRET_NAMES[@]:-}"; do
  [ -n "$secret_name" ] || continue
  PRESERVE_LIST="$PRESERVE_LIST,$secret_name"
done

# --- Resolve tool paths from THIS (invoking) user's PATH, once -------------
# Resolved to absolute, symlink-free paths and referenced that way
# everywhere below -- both so `nix-store -qR` (inside gen-profile.sh) gets
# real store paths, and so the final `sudo -u pi` invocation never depends
# on whatever (possibly minimal) PATH sudo's `secure_path` gives `pi` --
# see IMPLEMENTERS.md's UNVERIFIED list for why this is a judgement call,
# not a spike-verified fact.
NONO_BIN="$(resolve_or_die nono)"
PI_BIN="$(resolve_or_die pi)"
JQ_BIN="$(resolve_or_die jq)"
APPROVAL_HELPER_BIN="$(resolve_or_die approval-helper)"

# --extra-closure-root candidates for gen-profile.sh's Linux exec-ceiling
# closure (PLAN.md: "plus the stack's own tools (pi, node, the nix/scripts
# tools)"). node's own files come from the `node_runtime` nono group
# instead (see profiles/work.base.json), not from here. agent-validate/
# agent-plan-create are optional -- only added if found, since a plain
# interactive `pi` session (this script's only job) doesn't strictly need
# them the way an IMPLEMENT subagent does.
EXTRA_CLOSURE_ROOTS=("$PI_BIN")
for optional_tool in agent-validate agent-plan-create; do
  if tool_path="$(command -v "$optional_tool" 2>/dev/null)"; then
    EXTRA_CLOSURE_ROOTS+=("$(readlink -f "$tool_path")")
  fi
done
CLOSURE_ROOT_ARGS=()
for root in "${EXTRA_CLOSURE_ROOTS[@]}"; do
  CLOSURE_ROOT_ARGS+=(--extra-closure-root "$root")
done

if [ "$DRY_RUN" = "1" ]; then
  echo "==> --dry-run: no directories created, no helper started, no sudo/nono commands run." >&2
  echo "Resolved (illustrative -- the real webhook URL/profile path are only known once this actually runs):" >&2
  echo "  nono:                $NONO_BIN" >&2
  echo "  pi:                  $PI_BIN" >&2
  echo "  session name:        $SESSION_NAME" >&2
  echo "  workdir source:      $(pwd)" >&2
  echo "  extra-closure-roots: ${EXTRA_CLOSURE_ROOTS[*]}" >&2
  echo "  --add:               ${ADD_PATHS[*]:-<none>}" >&2
  echo "  --clone:             ${CLONE_PATHS[*]:-<none>}" >&2
  echo "  secrets (names only, values redacted): ${SECRET_NAMES[*]:-<none>}" >&2
  echo >&2
  echo "Resolved command (would run as the 'pi' user):" >&2
  nono_run_line="  $NONO_BIN run --profile /var/lib/pi/runs/$SESSION_NAME/profile.json --allow-cwd"
  [ "$AUDIT_FLAG" = "1" ] && nono_run_line="$nono_run_line --audit-integrity"
  [ "$DETACHED_FLAG" = "1" ] && nono_run_line="$nono_run_line --detached"
  nono_run_line="$nono_run_line --name $SESSION_NAME -- $PI_BIN"
  [ "$RESUME_FLAG" = "1" ] && nono_run_line="$nono_run_line --resume"
  {
    echo "  sudo -u pi --preserve-env=$PRESERVE_LIST -- \\"
    echo "    sh -c 'cd \"\$1\"; shift; exec \"\$@\"' sh /var/lib/pi/runs/$SESSION_NAME/workdir \\"
    echo "$nono_run_line"
  } >&2
  exit 0
fi

# --- Per-run, pi-owned state tree ------------------------------------------
RUN_DIR="$RUNS_ROOT/$SESSION_NAME"
PI_ROOT="$RUN_DIR/pi"
AGENT_DIR="$PI_ROOT/agent"
STATE_DIR="$RUN_DIR/state"
WORKDIR_DEST="$RUN_DIR/workdir"

# tar_copy_to_pi: streams the CONTENTS of a host directory (or a lone
# file) owned by the invoking user into a fresh pi-owned destination
# directory, without ever requiring `pi` to have read access to the
# source in place, and without requiring the invoking user to have any
# access into /var/lib/pi beyond running `sudo -u pi`. The source-side tar
# runs as the invoking user (who already owns/can read these files); only
# the destination-side tar runs as `pi`.
tar_copy_to_pi() {
  local src="$1" dest="$2"
  sudo -u pi mkdir -p "$dest"
  if [ -d "$src" ]; then
    tar -cf - -C "$src" . | sudo -u pi tar -xf - -C "$dest"
  else
    tar -cf - -C "$(dirname "$src")" "$(basename "$src")" | sudo -u pi tar -xf - -C "$dest"
  fi
}

# write_as_pi: pipes $2's contents into a pi-owned file at $1 (the
# invoking user never needs write access into /var/lib/pi for this --
# only `tee`, running as `pi`, does).
write_as_pi() {
  # shellcheck disable=SC2024 # intentional: the invoking user's shell
  # opens $2 for reading before exec'ing sudo -- `pi` never needs read
  # access to it, only `tee`'s write to $1 runs as `pi`.
  sudo -u pi tee "$1" <"$2" >/dev/null
}

echo "==> Seeding per-run state under $RUN_DIR (idempotent -- existing pi/session state is kept)..." >&2
sudo -u pi mkdir -p "$AGENT_DIR/extensions" "$AGENT_DIR/skills" "$STATE_DIR/auth" "$STATE_DIR/sessions"

echo "    building pi-extra-extensions/pi-extra-skills..." >&2
EXTRA_EXT_PATH="$(nix build "$STACK_DIR#pi-extra-extensions" --no-link --print-out-paths)"
EXTRA_SKILLS_PATH="$(nix build "$STACK_DIR#pi-extra-skills" --no-link --print-out-paths)"
# Nix store paths are world-readable, so `pi` can read them directly --
# only the destination write needs to run as `pi`.
sudo -u pi cp -r --no-preserve=mode "$EXTRA_EXT_PATH/." "$AGENT_DIR/extensions/"
sudo -u pi cp -r --no-preserve=mode "$EXTRA_SKILLS_PATH/." "$AGENT_DIR/skills/"

echo "    layering config/agent/ (fresh settings.json/AGENTS.md/agents/*)..." >&2
tar_copy_to_pi "$CONFIG_AGENT_DIR" "$AGENT_DIR"
if [ -f "$CONFIG_WEB_SEARCH" ]; then
  write_as_pi "$PI_ROOT/web-search.json" "$CONFIG_WEB_SEARCH"
fi

echo "    copying workdir ($(pwd))..." >&2
tar_copy_to_pi "$(pwd)" "$WORKDIR_DEST"

EXTRA_GEN_ARGS=()
add_counter=0
for add_path in "${ADD_PATHS[@]:-}"; do
  [ -n "$add_path" ] || continue
  add_counter=$((add_counter + 1))
  dest="$RUN_DIR/add-$add_counter"
  echo "    copying --add $add_path -> $dest..." >&2
  tar_copy_to_pi "$add_path" "$dest"
  EXTRA_GEN_ARGS+=(--add "$dest")
done
clone_counter=0
for clone_path in "${CLONE_PATHS[@]:-}"; do
  [ -n "$clone_path" ] || continue
  clone_counter=$((clone_counter + 1))
  dest="$RUN_DIR/clone-$clone_counter"
  echo "    copying --clone $clone_path -> $dest..." >&2
  tar_copy_to_pi "$clone_path" "$dest"
  EXTRA_GEN_ARGS+=(--clone "$dest")
done

if [ "$DETACHED_FLAG" != "1" ]; then
  # --- Foreground mode: approval helper and nono share this process's
  # lifetime. ---------------------------------------------------------
  INFO_FILE="$(mktemp -u)"
  HELPER_PID=""
  # shellcheck disable=SC2329 # invoked indirectly via `trap ... EXIT` below
  stop_helper() {
    if [ -n "$HELPER_PID" ] && kill -0 "$HELPER_PID" 2>/dev/null; then
      kill "$HELPER_PID" 2>/dev/null || true
    fi
    rm -f "$INFO_FILE"
  }
  trap stop_helper EXIT

  "$APPROVAL_HELPER_BIN" --ui auto --info-file "$INFO_FILE" --parent-pid "$$" &
  HELPER_PID=$!
  for _ in $(seq 1 50); do
    [ -s "$INFO_FILE" ] && break
    sleep 0.1
  done
  if [ ! -s "$INFO_FILE" ]; then
    echo "error: approval helper never wrote its startup info file -- check its stderr output above." >&2
    exit 1
  fi
  WEBHOOK_URL="$("$JQ_BIN" -r .url "$INFO_FILE")"

  echo "==> Generating the nono profile..." >&2
  TMP_PROFILE="$(mktemp)"
  "$GEN_PROFILE_SH" --base "$BASE_PROFILE" --out "$TMP_PROFILE" \
    --webhook-url "$WEBHOOK_URL" --workdir "$WORKDIR_DEST" --state-dir "$STATE_DIR" \
    "${EXTRA_GEN_ARGS[@]}" "${CLOSURE_ROOT_ARGS[@]}"
  write_as_pi "$RUN_DIR/profile.json" "$TMP_PROFILE"
  rm -f "$TMP_PROFILE"

  export PI_CODING_AGENT_DIR="$AGENT_DIR"
  export XDG_STATE_HOME="$STATE_DIR"

  NONO_ARGS=(run --profile "$RUN_DIR/profile.json" --allow-cwd)
  [ "$AUDIT_FLAG" = "1" ] && NONO_ARGS+=(--audit-integrity)
  NONO_ARGS+=(--name "$SESSION_NAME" -- "$PI_BIN")
  [ "$RESUME_FLAG" = "1" ] && NONO_ARGS+=(--resume)

  echo "==> Starting nono as 'pi' (session: $SESSION_NAME)..." >&2
  sudo -u pi --preserve-env="$PRESERVE_LIST" -- \
    sh -c 'cd "$1"; shift; exec "$@"' sh "$WORKDIR_DEST" \
    "$NONO_BIN" "${NONO_ARGS[@]}"
  exit $?
fi

# --- Detached mode: a supervisor outlives this launcher --------------------
# A small, self-contained script (not this process) owns the rest of the
# lifecycle: starting the approval helper, generating the profile, running
# `nono run --detached`, and -- once that returns -- polling `nono ps`
# until the session itself is gone, at which point it stops the approval
# helper and exits. It runs AS `pi` the whole time (via `sudo -u pi`
# wrapping the one `setsid`/background invocation below), detached from
# this launcher's own session so it survives this process exiting.
#
# UNVERIFIED judgement call: no nono binary was available in this
# environment to confirm `nono ps`'s exact output shape beyond what
# spikes/all/run.sh's S5.1-S5.3 already exercised (plain `nono ps`, grepped
# for the session name) -- see IMPLEMENTERS.md.
echo "==> --detached: starting a supervisor (logs: $RUN_DIR/supervisor.log)..." >&2

SUPERVISOR_SCRIPT="$RUN_DIR/supervisor.sh"
TMP_SUPERVISOR="$(mktemp)"
GEN_ARGS_QUOTED="$(printf '%q ' "${EXTRA_GEN_ARGS[@]}" "${CLOSURE_ROOT_ARGS[@]}")"
# Precomputed as plain strings (rather than inline conditionals inside the
# heredoc below) so the generated script never needs a conditional
# line-continuation -- much easier to get right than juggling printf/
# backslash escaping inside an already-escaped heredoc.
NONO_RUN_EXTRA_FLAGS=""
[ "$AUDIT_FLAG" = "1" ] && NONO_RUN_EXTRA_FLAGS=" --audit-integrity"
PI_RESUME_SUFFIX=""
[ "$RESUME_FLAG" = "1" ] && PI_RESUME_SUFFIX=" --resume"
cat >"$TMP_SUPERVISOR" <<SUPERVISOR
#!/usr/bin/env bash
set -uo pipefail
INFO_FILE="$RUN_DIR/approval-helper-info.json"
"$APPROVAL_HELPER_BIN" --ui auto --info-file "\$INFO_FILE" &
HELPER_PID=\$!
for _ in \$(seq 1 50); do [ -s "\$INFO_FILE" ] && break; sleep 0.1; done
WEBHOOK_URL="\$("$JQ_BIN" -r .url "\$INFO_FILE")"

TMP_PROFILE="\$(mktemp)"
"$GEN_PROFILE_SH" --base "$BASE_PROFILE" --out "\$TMP_PROFILE" \\
  --webhook-url "\$WEBHOOK_URL" --workdir "$WORKDIR_DEST" --state-dir "$STATE_DIR" \\
  $GEN_ARGS_QUOTED
cp "\$TMP_PROFILE" "$RUN_DIR/profile.json"
rm -f "\$TMP_PROFILE"

export PI_CODING_AGENT_DIR="$AGENT_DIR"
export XDG_STATE_HOME="$STATE_DIR"
cd "$WORKDIR_DEST"
"$NONO_BIN" run --profile "$RUN_DIR/profile.json" --allow-cwd$NONO_RUN_EXTRA_FLAGS --detached --name "$SESSION_NAME" -- "$PI_BIN"$PI_RESUME_SUFFIX

while "$NONO_BIN" ps 2>/dev/null | grep -q "$SESSION_NAME"; do
  sleep 5
done
kill "\$HELPER_PID" 2>/dev/null || true
rm -f "\$INFO_FILE"
SUPERVISOR
write_as_pi "$SUPERVISOR_SCRIPT" "$TMP_SUPERVISOR"
sudo -u pi chmod +x "$SUPERVISOR_SCRIPT"
rm -f "$TMP_SUPERVISOR"

# The log redirect must happen INSIDE the sudo'd process (as `pi`): the
# invoking user has no write access into $RUN_DIR to open that file
# itself before exec'ing sudo.
# shellcheck disable=SC2016 # intentional: $1/$2 are this `bash -c`
# script's OWN positional params, deferred until it runs -- not meant to
# expand in the launcher's shell.
setsid sudo -u pi --preserve-env="$PRESERVE_LIST" -- \
  bash -c 'exec bash "$1" >"$2" 2>&1 </dev/null' bash \
  "$SUPERVISOR_SCRIPT" "$RUN_DIR/supervisor.log" &
disown

echo "==> Detached session '$SESSION_NAME' starting (see $RUN_DIR/supervisor.log). Use the (Phase 4b) ps/attach/stop wrappers once built." >&2
