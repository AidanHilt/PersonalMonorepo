#!/usr/bin/env bash
# nix run $PERSONAL_MONOREPO_LOCATION/nix/agentic-ai-stack#start-agent
#
# Acceptance criterion (spec §11): a fresh host produces a working
# pi+proxy stack with no manual steps beyond providing credentials —
# this script builds/loads images and brings the compose stack up;
# `nix run $PERSONAL_MONOREPO_LOCATION/nix/agentic-ai-stack#stop-agent` tears it down.
set -euo pipefail

# --- Kubeconfig: always attempted, never required -------------------------
# We no longer hard-fail when no kubeconfig is present. If a scoped
# kubeconfig exists (default path below, or PI_SANDBOX__KUBECONFIG_PATH), we
# layer compose.kube.yaml on top to mount it read-only into the `pi`
# container. If it's missing, we warn and continue without k8s access
# rather than blocking the whole stack on it.
KUBECONFIG_PATH="${PI_SANDBOX__KUBECONFIG_PATH:-$HOME/.config/pi-sandbox/agent-kubeconfig.yaml}"
COMPOSE_FILES=(-f compose.yaml)

# --- Secrets: arbitrary-name injection, never decrypted here --------------
# This script performs NO secret retrieval/decryption of its own. It only
# accepts already-decrypted values via two channels and forwards them into
# the `pi` container as `-e NAME=VALUE` on `docker compose run`:
#   1. Repeatable `--secret NAME=VALUE` CLI flags.
#   2. Host env vars namespaced `PI_SANDBOX__SECRET__<NAME>` (prefix
#      stripped to get NAME).
# The namespace scan runs first, then `--secret` flags are appended after
# it, so a `--secret` flag always wins over a same-named namespaced env var
# (later `-e` wins when docker encounters a duplicate name).
SECRET_ENV_ARGS=()

# --- pkg-broker store backend: CLI flag alias for the env var below -------
# '--host-store' is a plain boolean alias for PI_SANDBOX__PKGBROKER_HOST_STORE=1,
# parsed here alongside '--secret' so both can be combined in one invocation.
# Either the flag or the env var being '1' is enough to opt in (OR semantics).
HOST_STORE_FLAG=0

# --- Session naming / resume: CLI flags for pi's own --name/--resume -----
# '--name NAME' / '--name=NAME' sets a prefix for this run's session
# display name; the actual name passed into the container is always
# "${NAME:-pi}-$(date +%Y%m%d-%H%M%S)" (computed below, once, right before
# the final `docker compose run`), so re-running with the same --name
# never collides with a previous session. '--resume' is a plain boolean
# that instead tells the container to run pi's own built-in interactive
# session picker (`pi --resume`) against the pi-sessions volume -- no name
# is set in that case. The two are mutually exclusive (checked once both
# are fully parsed, below). Neither flag has a matching
# PI_SANDBOX__PERSIST_*-style env var: both are forwarded into the
# container purely as `-e PI_SANDBOX__SESSION_NAME=...` /
# `-e PI_SANDBOX__RESUME=1` on the final `docker compose run`, the same
# mechanism SECRET_ENV_ARGS uses (see containers/pi/entrypoint.sh for how
# they're consumed).
NAME_FLAG=""
RESUME_FLAG=0

# --- Persistence: pkg-bin / nix-store / proxy-domains volumes -------------
# Defaults (see compose.yaml's top-level `volumes:` comment and
# README.md): pkg-bin=ephemeral, nix-store=persistent, proxy-domains=
# ephemeral. Only flags that CHANGE a default exist (no --no-persist-pkgs,
# no --persist-store, no --no-persist-domains) -- but the matching
# PI_SANDBOX__PERSIST_* env var may express either value. A CLI flag
# always overrides its env var. "Ephemeral" means this script removes the
# volume with an explicit `docker volume rm` (never tmpfs, never an
# `external: true` volume) -- see compose.yaml. pi-auth/pi-sessions are
# NEVER touched by this logic.
PERSIST_PKGS_FLAG=""
PERSIST_STORE_FLAG=""
PERSIST_DOMAINS_FLAG=""

print_help() {
  cat <<'EOF'
Usage: start-agent.sh [FLAGS]

Brings up the pi+proxy+pkg-broker compose stack (nix run .#start-agent).

Flags:
  --add PATH               Mount an existing host file/directory into
                            /workspace (repeatable). See README.md.
  --clone URL               Clone a URL on the host and mount it into
                            /workspace (repeatable). See README.md.
  --secret NAME=VALUE       Inject an already-decrypted secret as an env
                            var into the pi container (repeatable).
  --name NAME, --name=NAME Prefix for this run's session display name
                            (the container gets "NAME-YYYYmmdd-HHMMSS";
                            default prefix is 'pi'). Mutually exclusive
                            with --resume.
  --resume                   Skip naming a new session and instead run
                            pi's own built-in --resume session picker
                            inside the container (pi-sessions volume).
                            Mutually exclusive with --name. Has no
                            effect if PI_SESSIONS=0 is set on the pi
                            container (sessions disabled).
  --host-store               Alias for PI_SANDBOX__PKGBROKER_HOST_STORE=1:
                            pkg-broker shares the host's real /nix/store +
                            nix-daemon instead of its own isolated volume.
  --persist-pkgs             Keep the pkg-bin volume (pkg-broker's
                            resolved binaries) across runs instead of
                            removing it on teardown. Default: off
                            (ephemeral).
  --no-persist-store         Remove the nix-store volume (pkg-broker's
                            own nix store) on teardown instead of keeping
                            it. Default: on (persistent). Mutually
                            exclusive with --host-store (nix-store is
                            unused in that mode).
  --persist-domains          Keep runtime request-domain grants
                            (dynamic-domains.txt, see domain-gate) across
                            proxy restarts instead of clearing them on
                            every start. Default: off (cleared every
                            start).
  --help, -h                  Show this help and exit. No docker/sudo/nix
                            work is performed.

Environment variables (a CLI flag above always overrides the matching one):
  PI_SANDBOX__PERSIST_PKGS=0|1          Same as --persist-pkgs. Default: 0.
  PI_SANDBOX__PERSIST_STORE=0|1         Inverse of --no-persist-store.
                                         Default: 1.
  PI_SANDBOX__PERSIST_DOMAINS=0|1       Same as --persist-domains.
                                         Default: 0.
  PI_SANDBOX__PKGBROKER_HOST_STORE=0|1  Same as --host-store.
  PI_SANDBOX__KUBECONFIG_PATH           Override the default kubeconfig
                                         path.
  PI_SANDBOX__SECRET__<NAME>            Same as --secret NAME=VALUE.
  PERSONAL_MONOREPO_LOCATION             Path to the monorepo checkout.

Session naming / resume (no matching env var to set directly -- these are
computed by this script from --name/--resume and forwarded into the pi
container as PI_SANDBOX__SESSION_NAME / PI_SANDBOX__RESUME, consumed by
containers/pi/entrypoint.sh):
  --name NAME / --name=NAME             Prefix for this run's session name.
  --resume                               Open pi's built-in session picker
                                         instead.

See README.md for the full writeup (persistence model, workspace extras,
secrets, kubeconfig, store backends).
EOF
}

# --- Workspace contents: repeatable --add PATH / --clone URL --------------
# /workspace has NO default content anymore (no more implicit
# PERSONAL_MONOREPO_LOCATION bind mount, see compose.yaml). What `pi` sees
# at /workspace is built up entirely from these two repeatable flags, in the
# order given:
#   --add PATH    an existing host file or directory, resolved to an
#                 absolute realpath.
#   --clone URL   cloned on the HOST (so host git credentials/ssh-agent/
#                 credential helpers are used, not anything inside the
#                 container) into
#                 ${XDG_CACHE_HOME:-$HOME/.cache}/pi-sandbox/clones/<repo-name>
#                 (<repo-name> = URL basename, .git suffix stripped). If
#                 that clone already exists, only `git fetch` runs -- the
#                 working tree is never touched -- then it's treated
#                 exactly like `--add <that dir>`.
# Layout rules (see compose.workspace.yaml / containers/workspace-mounter):
#   - Zero extras: /workspace is an empty tmpfs (no sidecar is started).
#   - Exactly one extra, a directory: mounted directly AT /workspace.
#   - Exactly one extra, a file: rejected -- a lone --add/--clone must
#     resolve to a directory.
#   - Two or more extras: /workspace is a neutral root; each extra (file or
#     directory) appears as a sibling at /workspace/<basename>.
# Two extras sharing a basename is an error (ambiguous sibling name).
EXTRAS=()  # ordered "name:type:hostpath" entries; type is "dir" or "file"

add_extra() {
  local hostpath="$1" type="$2" name existing existing_name
  name="$(basename "$hostpath")"
  for existing in "${EXTRAS[@]:-}"; do
    [ -n "$existing" ] || continue
    existing_name="${existing%%:*}"
    if [ "$existing_name" = "$name" ]; then
      echo "error: two --add/--clone extras share the same basename '$name' ($hostpath vs. the earlier one) -- rename/relocate one of them." >&2
      exit 1
    fi
  done
  EXTRAS+=("$name:$type:$hostpath")
}

handle_add() {
  local add_path="${1:?--add requires a PATH argument}" resolved
  if [ ! -e "$add_path" ]; then
    echo "error: --add path does not exist: $add_path" >&2
    exit 1
  fi
  resolved="$(realpath "$add_path")"
  if [ -d "$resolved" ]; then
    add_extra "$resolved" dir
  elif [ -f "$resolved" ]; then
    add_extra "$resolved" file
  else
    echo "error: --add path is neither a regular file nor a directory: $resolved" >&2
    exit 1
  fi
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
    echo "==> --clone: $repo_name already cloned at $dest -- fetching only (working tree left untouched)."
    git -C "$dest" fetch
  else
    echo "==> --clone: cloning $url into $dest..."
    git clone "$url" "$dest"
  fi
  add_extra "$dest" dir
}

while [ $# -gt 0 ]; do
  case "$1" in
    --help|-h)
      print_help
      exit 0
      ;;
    --host-store)
      HOST_STORE_FLAG=1
      shift
      ;;
    --persist-pkgs)
      PERSIST_PKGS_FLAG=1
      shift
      ;;
    --no-persist-store)
      PERSIST_STORE_FLAG=0
      shift
      ;;
    --persist-domains)
      PERSIST_DOMAINS_FLAG=1
      shift
      ;;
    --name)
      shift
      NAME_FLAG="${1:?--name requires a NAME argument}"
      shift
      ;;
    --name=*)
      NAME_FLAG="${1#--name=}"
      shift
      ;;
    --resume)
      RESUME_FLAG=1
      shift
      ;;
    --add)
      shift
      handle_add "${1:?--add requires a PATH argument}"
      shift
      ;;
    --add=*)
      handle_add "${1#--add=}"
      shift
      ;;
    --clone)
      shift
      handle_clone "${1:?--clone requires a URL argument}"
      shift
      ;;
    --clone=*)
      handle_clone "${1#--clone=}"
      shift
      ;;
    --secret)
      shift
      secret_arg="${1:?--secret requires a NAME=VALUE argument}"
      secret_name="${secret_arg%%=*}"
      if [ -z "$secret_name" ] || [ "$secret_arg" = "${secret_arg#*=}" ]; then
        echo "error: --secret requires a NAME=VALUE argument with a non-empty NAME (got: $secret_arg)" >&2
        exit 1
      fi
      SECRET_ENV_ARGS+=(-e "$secret_arg")
      shift
      ;;
    --secret=*)
      secret_arg="${1#--secret=}"
      secret_name="${secret_arg%%=*}"
      if [ -z "$secret_name" ] || [ "$secret_arg" = "${secret_arg#*=}" ]; then
        echo "error: --secret requires a NAME=VALUE argument with a non-empty NAME (got: $secret_arg)" >&2
        exit 1
      fi
      SECRET_ENV_ARGS+=(-e "$secret_arg")
      shift
      ;;
    *)
      echo "error: unrecognized argument: $1" >&2
      exit 1
      ;;
  esac
done

if [ "$RESUME_FLAG" = "1" ] && [ -n "$NAME_FLAG" ]; then
  echo "error: --resume and --name are mutually exclusive -- --resume runs pi's own session picker instead of starting a newly-named session." >&2
  exit 1
fi

# Computed once, here, and forwarded into the pi container purely as env
# vars (see containers/pi/entrypoint.sh) -- same -e mechanism as
# SECRET_ENV_ARGS, appended separately below so secrets-flag precedence
# semantics (namespace-scan-then-flags) are untouched.
SESSION_ENV_ARGS=()
if [ "$RESUME_FLAG" = "1" ]; then
  echo "==> --resume: this run will open pi's built-in session picker instead of starting a newly-named session."
  SESSION_ENV_ARGS+=(-e "PI_SANDBOX__RESUME=1")
else
  SESSION_NAME="${NAME_FLAG:-pi}-$(date +%Y%m%d-%H%M%S)"
  echo "==> Session name: $SESSION_NAME"
  SESSION_ENV_ARGS+=(-e "PI_SANDBOX__SESSION_NAME=$SESSION_NAME")
fi

SECRET_NAMESPACE_ARGS=()
while IFS= read -r var_name; do
  [ -n "$var_name" ] || continue
  secret_name="${var_name#PI_SANDBOX__SECRET__}"
  SECRET_NAMESPACE_ARGS+=(-e "${secret_name}=${!var_name}")
done < <(compgen -v PI_SANDBOX__SECRET__ || true)

# Namespace-discovered values first, explicit --secret flags appended
# after, so flags take precedence on a NAME collision.
SECRET_ENV_ARGS=("${SECRET_NAMESPACE_ARGS[@]}" "${SECRET_ENV_ARGS[@]}")

echo "==> Checking for a generated kubeconfig..."
if [ -f "$KUBECONFIG_PATH" ]; then
  echo "    found: $KUBECONFIG_PATH — enabling k8s access for this run."
  COMPOSE_FILES+=(-f compose.kube.yaml)
else
  cat >&2 <<EOF
    WARNING: no kubeconfig found at $KUBECONFIG_PATH.
    Continuing WITHOUT Kubernetes access for this run.
    To enable it, generate a scoped, dev/staging-only kubeconfig with:
      nix run $PERSONAL_MONOREPO_LOCATION/nix/agentic-ai-stack#gen-kubeconfig
    (or place a pre-generated one at $KUBECONFIG_PATH / set PI_SANDBOX__KUBECONFIG_PATH)
EOF
fi

# --- pkg-broker store backend: default isolated volume vs. host-shared ----
# Mirrors the kubeconfig block above: an opt-in override, layered onto
# COMPOSE_FILES, rather than something this script decides on its own.
# Set PI_SANDBOX__PKGBROKER_HOST_STORE=1 (or pass '--host-store') to swap
# pkg-broker's default, empty 'nix-store' docker volume for the host's real
# /nix/store + 
# nix-daemon socket (compose.pkgbroker-host-store.yaml -- see
# containers/pkg-broker/README.md for the trust-boundary tradeoff that
# override makes). Resolved again, below, once we know which backend is
# active, to decide what pi's own /nix/store bind mount should point at.
if [ "$HOST_STORE_FLAG" = "1" ] || [ "${PI_SANDBOX__PKGBROKER_HOST_STORE:-0}" = "1" ]; then
  PKGBROKER_HOST_STORE=1
else
  PKGBROKER_HOST_STORE=0
fi
echo "==> Checking pkg-broker store backend..."
if [ "$PKGBROKER_HOST_STORE" = "1" ]; then
  echo "    PI_SANDBOX__PKGBROKER_HOST_STORE=1 / --host-store — layering compose.pkgbroker-host-store.yaml (pkg-broker shares the host's real nix store/daemon)."
  COMPOSE_FILES+=(-f compose.pkgbroker-host-store.yaml)
else
  echo "    Using pkg-broker's default, isolated 'nix-store' volume (set PI_SANDBOX__PKGBROKER_HOST_STORE=1 or pass --host-store to share the host's real store instead)."
  COMPOSE_FILES+=(-f compose.nixstore-overlay.yaml)
fi

# --- Resolve persistence choices (flag > env var > default) ---------------
if [ -n "$PERSIST_PKGS_FLAG" ]; then
  PERSIST_PKGS="$PERSIST_PKGS_FLAG"
else
  PERSIST_PKGS="${PI_SANDBOX__PERSIST_PKGS:-0}"
fi
if [ -n "$PERSIST_STORE_FLAG" ]; then
  PERSIST_STORE="$PERSIST_STORE_FLAG"
else
  PERSIST_STORE="${PI_SANDBOX__PERSIST_STORE:-1}"
fi
if [ -n "$PERSIST_DOMAINS_FLAG" ]; then
  PERSIST_DOMAINS="$PERSIST_DOMAINS_FLAG"
else
  PERSIST_DOMAINS="${PI_SANDBOX__PERSIST_DOMAINS:-0}"
fi

if [ "$PERSIST_STORE" = "0" ] && [ "$PKGBROKER_HOST_STORE" = "1" ]; then
  echo "error: --no-persist-store / PI_SANDBOX__PERSIST_STORE=0 is mutually exclusive with --host-store / PI_SANDBOX__PKGBROKER_HOST_STORE=1 (the nix-store volume is unused in host-store mode)." >&2
  exit 1
fi
if [ "$PERSIST_PKGS" = "1" ] && [ "$PERSIST_STORE" = "0" ]; then
  echo "    WARNING: --persist-pkgs together with --no-persist-store will leave pkg-bin's symlinks dangling after teardown (they point into paths inside the nix-store volume, which will be removed). Consider persisting both or neither." >&2
fi

export PI_SANDBOX__PERSIST_DOMAINS="$PERSIST_DOMAINS"

echo "==> Persistence: pkg-bin=$( [ "$PERSIST_PKGS" = "1" ] && echo persistent || echo ephemeral ), nix-store=$( [ "$PERSIST_STORE" = "1" ] && echo persistent || echo ephemeral ), proxy-domains=$( [ "$PERSIST_DOMAINS" = "1" ] && echo persistent || echo ephemeral )"

# Removes any of pkg-bin/nix-store/proxy-domains NOT marked persistent
# above, resolving their actual (project-name-prefixed) volume names via
# `docker compose config` rather than hardcoding a project-name prefix.
# Called twice: once below (before `up`, to clear leftovers from a
# crashed previous run) and once more from cleanup() after `down`.
# pi-auth/pi-sessions are never referenced here -- they must never be
# removed.
remove_nonpersisted_volumes() {
  local volumes_json pkg_bin_vol nix_store_vol proxy_domains_vol
  volumes_json="$(docker compose "${COMPOSE_FILES[@]}" config --format json 2>/dev/null)" || return 0
  pkg_bin_vol="$(jq -r '.volumes["pkg-bin"].name // empty' <<<"$volumes_json")"
  nix_store_vol="$(jq -r '.volumes["nix-store"].name // empty' <<<"$volumes_json")"
  proxy_domains_vol="$(jq -r '.volumes["proxy-domains"].name // empty' <<<"$volumes_json")"

  if [ "$PERSIST_PKGS" != "1" ] && [ -n "$pkg_bin_vol" ]; then
    echo "    removing non-persisted volume: $pkg_bin_vol (pkg-bin -- pass --persist-pkgs to keep it)"
    docker volume rm "$pkg_bin_vol" >/dev/null 2>&1 || true
  fi
  if [ "$PERSIST_STORE" != "1" ] && [ -n "$nix_store_vol" ]; then
    echo "    removing non-persisted volume: $nix_store_vol (nix-store -- omit --no-persist-store to keep it)"
    docker volume rm "$nix_store_vol" >/dev/null 2>&1 || true
  fi
  if [ "$PERSIST_DOMAINS" != "1" ] && [ -n "$proxy_domains_vol" ]; then
    echo "    removing non-persisted volume: $proxy_domains_vol (proxy-domains -- pass --persist-domains to keep it)"
    docker volume rm "$proxy_domains_vol" >/dev/null 2>&1 || true
  fi
}

# --- Local Ollama support: DEPRECATED --------------------------------------
# The native-Ollama-on-host flow below is deprecated and disabled. We may
# revisit local AI in the future; leaving the logic here (commented out)
# rather than deleting it in case we do.
#
# echo "==> Verifying Ollama is reachable natively on the host..."
# OLLAMA_HOST_URL="${OLLAMA_HOST_URL:-http://127.0.0.1:11434}"
# if ! curl -fsS --max-time 3 "$OLLAMA_HOST_URL/api/version" >/dev/null 2>&1; then
# cat >&2 <<EOF
#     Ollama does not appear to be running at $OLLAMA_HOST_URL.
#     This stack runs Ollama natively on the host, not in a container
#     (spec §3.3 — GPU passthrough overhead). Start it first:
#       macOS:  ollama serve   (or the Ollama.app menu-bar app)
#       NixOS:  systemctl --user start ollama   (or: services.ollama.enable = true;)
#     Then re-run this script.
# EOF
# exit 1
# fi
# echo "    OK: Ollama is up."

cd "$PERSONAL_MONOREPO_LOCATION/nix/agentic-ai-stack"

# --- Resolve the workspace layout from the --add/--clone extras above -----
# Must run from the stack dir (cd above) since the generated extras compose
# file is written under the same cache root as the other merged-dir state.
WORKSPACE_MODE="empty"
if [ "${#EXTRAS[@]}" -eq 1 ]; then
  IFS=':' read -r _ex_name ex_type _ex_path <<< "${EXTRAS[0]}"
  if [ "$ex_type" = "file" ]; then
    echo "error: a single --add/--clone extra must be a directory (got a file). Pass a second extra to use sibling mode, or point --add at its containing directory instead." >&2
    exit 1
  fi
  WORKSPACE_MODE="single"
elif [ "${#EXTRAS[@]}" -gt 1 ]; then
  WORKSPACE_MODE="sibling"
fi

WORKSPACE_MERGED_DIR=""
if [ "$WORKSPACE_MODE" != "empty" ]; then
  echo "==> Preparing workspace staging directory (populated by workspace-mounter)..."
  WORKSPACE_MERGED_DIR="${PI_SANDBOX__WORKSPACE_MERGED_DIR:-${XDG_CACHE_HOME:-$HOME/.cache}/pi-sandbox/workspace-merged}"
   if ! stat "$WORKSPACE_MERGED_DIR" >/dev/null 2>&1 \
      && grep -q " $WORKSPACE_MERGED_DIR " /proc/self/mountinfo; then
     echo "Stale mount at $WORKSPACE_MERGED_DIR; clearing (needs sudo)..." >&2
     sudo umount -l "$WORKSPACE_MERGED_DIR"
   fi
   mkdir -p "$WORKSPACE_MERGED_DIR"

  # A leftover mount (crashed mounter) would shadow the fresh one.
  while mountpoint -q "$WORKSPACE_MERGED_DIR"; do
    echo "    stale mount found at $WORKSPACE_MERGED_DIR -- unmounting (sudo)."
    sudo umount "$WORKSPACE_MERGED_DIR"
  done

  # Docker only accepts rshared/rslave binds from a shared (or slave) mount.
  prop="$(findmnt -n -o PROPAGATION -T "$WORKSPACE_MERGED_DIR" 2>/dev/null || true)"
  case "$prop" in
    *shared*|*slave*) ;;
    *) echo "    WARNING: $WORKSPACE_MERGED_DIR is on a mount with propagation '${prop:-unknown}', not shared." >&2
       echo "    The merged workspace will not be visible to pi. Fix with: sudo mount --make-rshared /" >&2 ;;
  esac

  export PI_SANDBOX__WORKSPACE_SOURCE="$WORKSPACE_MERGED_DIR"
  export WORKSPACE_MODE
  export WORKSPACE_HOST_UID
  export WORKSPACE_HOST_GID
  
  WORKSPACE_HOST_UID="$(id -u)"
  WORKSPACE_HOST_GID="$(id -g)"

  # One bind-mount volume per extra, feeding the workspace-mounter service
  # (compose.workspace.yaml) -- generated fresh each run since the set of
  # extras is only known at invocation time, not something a static compose
  # file can express. WORKSPACE_ITEMS (an ordered "name:type,..." list,
  # exported below) tells containers/workspace-mounter/mount.sh how to
  # consume each of these mounted sources by matching index/name.
  WORKSPACE_EXTRAS_COMPOSE_FILE="${XDG_CACHE_HOME:-$HOME/.cache}/pi-sandbox/compose.workspace-extras.generated.yaml"
  mkdir -p "$(dirname "$WORKSPACE_EXTRAS_COMPOSE_FILE")"
  {
    echo "# Auto-generated by start-agent.sh -- do not edit by hand, regenerated"
    echo "# fresh on every invocation. Adds one bind-mount source volume per"
    echo "# --add/--clone extra to the workspace-mounter service defined in"
    echo "# compose.workspace.yaml."
    echo "services:"
    echo "  workspace-mounter:"
    echo "    volumes:"
    items_str=""
    for extra in "${EXTRAS[@]}"; do
      IFS=':' read -r ex_name ex_type ex_path <<< "$extra"
      if [ -n "$items_str" ]; then items_str+=","; fi
      items_str+="${ex_name}:${ex_type}"
      # Directory extras: bind the directory itself. File extras: bind the
      # file's PARENT directory (mount.sh bindfs-translates that whole
      # parent internally, then exposes only the one file) -- see
      # containers/workspace-mounter/mount.sh for why.
      if [ "$ex_type" = "dir" ]; then
        host_mount_src="$ex_path"
      else
        host_mount_src="$(dirname "$ex_path")"
      fi
      printf '      - type: bind\n        source: "%s"\n        target: "/srv/sources/%s"\n' "$host_mount_src" "$ex_name"
    done
    # shellcheck disable=SC2034
    export WORKSPACE_ITEMS="$items_str"
  } > "$WORKSPACE_EXTRAS_COMPOSE_FILE"

  echo "    layering compose.workspace.yaml + generated extras file (mode=$WORKSPACE_MODE, items=$WORKSPACE_ITEMS)"
  COMPOSE_FILES+=(-f compose.workspace.yaml -f "$WORKSPACE_EXTRAS_COMPOSE_FILE")
else
  echo "==> No --add/--clone extras given -- /workspace will start empty (tmpfs, no workspace-mounter)."
fi

echo "==> Building and loading pi/proxy/pkg-broker images into the active Docker context..."
DOCKER_CTX="$(docker context show 2>/dev/null || echo 'default')"
echo "    Active Docker context: $DOCKER_CTX"

override_flag=()
if [ -n "${PERSONAL_MONOREPO_LOCATION:-}" ] && [ -d "$PERSONAL_MONOREPO_LOCATION/nix/scripts" ]; then
  override_flag=(--override-input scripts "path:$PERSONAL_MONOREPO_LOCATION/nix/scripts")
  echo "==> Using local nix/scripts checkout at $PERSONAL_MONOREPO_LOCATION/nix/scripts"
fi

nix run "$PERSONAL_MONOREPO_LOCATION/nix/agentic-ai-stack#load" "${override_flag[@]}"

# --- pi's /nix/store source -------------------------------------------------
# - Host-store mode: pkg-broker shares the host's real /nix, and `nix run
#   .#load` already realized pi's closure there, so pi just binds the host's
#   /nix/store read-only.
# - Default mode: pi's /nix/store is the union of pi's OWN image store and the
#   shared nix-store volume (what pkg-broker builds). That union is built by
#   the nix-store-mounter service (compose.nixstore-overlay.yaml), which runs
#   the pi image with CAP_SYS_ADMIN and publishes the overlay to a host
#   directory via mount propagation; pi binds that directory (rslave). No
#   host-side overlay, no `sudo mount`, no reaching into docker volume dirs,
#   and pkg-broker never sees pi's closure.
UP_SERVICES=(proxy pkg-broker)
if [ "$PKGBROKER_HOST_STORE" = "1" ]; then
  echo "==> pkg-broker host-store override is active -- pi will bind the host's real /nix/store directly."
  export PI_SANDBOX__NIX_STORE_SOURCE="/nix/store"
else
  NIX_STORE_MERGED_DIR="${PI_SANDBOX__NIX_STORE_MERGED_DIR:-${XDG_CACHE_HOME:-$HOME/.cache}/pi-sandbox/nix-store-merged}"
  echo "==> Preparing merged /nix/store directory $NIX_STORE_MERGED_DIR (populated by nix-store-mounter)..."
  mkdir -p "$NIX_STORE_MERGED_DIR"

  # A leftover overlay (crashed mounter) would be stacked under the new one
  # and hold stale lower layers, so clear it first.
  while mountpoint -q "$NIX_STORE_MERGED_DIR"; do
    echo "    stale mount found at $NIX_STORE_MERGED_DIR -- unmounting (sudo)."
    sudo umount "$NIX_STORE_MERGED_DIR"
  done

  # Docker only accepts rshared/rslave binds from a shared (or slave) mount.
  prop="$(findmnt -n -o PROPAGATION -T "$NIX_STORE_MERGED_DIR" 2>/dev/null || true)"
  case "$prop" in
    *shared*|*slave*) ;;
    *) echo "    WARNING: $NIX_STORE_MERGED_DIR is on a mount with propagation '${prop:-unknown}', not shared." >&2
       echo "    The overlay will not be visible to pi. Fix with: sudo mount --make-rshared /" >&2 ;;
  esac

  export PI_SANDBOX__NIX_STORE_SOURCE="$NIX_STORE_MERGED_DIR"
  UP_SERVICES+=(nix-store-mounter)
fi

if [ -n "$WORKSPACE_MERGED_DIR" ]; then
  UP_SERVICES+=(workspace-mounter)
fi

echo "==> Clearing any leftover non-persisted volumes from a previous/crashed run..."
remove_nonpersisted_volumes

echo "==> Starting docker compose stack (pi + proxy + pkg-broker${NIX_STORE_MERGED_DIR:+ + nix-store-mounter}${WORKSPACE_MERGED_DIR:+ + workspace-mounter})..."
docker compose "${COMPOSE_FILES[@]}" up -d --wait "${UP_SERVICES[@]}"

cleanup() {
echo "==> Session finished — tearing down the compose stack..."
docker compose "${COMPOSE_FILES[@]}" down --remove-orphans
echo "==> Removing non-persisted volumes..."
remove_nonpersisted_volumes
if [ -n "${NIX_STORE_MERGED_DIR:-}" ]; then
  # nix-store-mounter unmounts on SIGTERM; this only catches a killed one.
  while mountpoint -q "$NIX_STORE_MERGED_DIR" 2>/dev/null; do
    sudo umount "$NIX_STORE_MERGED_DIR" || break
  done
fi
if [ -n "${WORKSPACE_MERGED_DIR:-}" ]; then
  # workspace-mounter unmounts on SIGTERM; this only catches a killed one.
  while mountpoint -q "$WORKSPACE_MERGED_DIR" 2>/dev/null; do
    sudo umount "$WORKSPACE_MERGED_DIR" || break
  done
fi
}
trap cleanup EXIT

docker compose "${COMPOSE_FILES[@]}" run --rm "${SECRET_ENV_ARGS[@]}" "${SESSION_ENV_ARGS[@]}" pi