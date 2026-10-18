#!/bin/bash
# Declarative option/positional parsing + generated help text.
#
# Usage (from a run.sh that also declares "# @lib: args-and-help"):
#
#   args_description "What this script does"
#   args_example "$(basename "$0") -n production -p my-data-pvc"
#   args_value "-n" "--namespace" NAMESPACE "NAMESPACE" "Kubernetes namespace to use"
#   args_flag "" "--force" FORCE "Skip confirmation"
#   args_repeat "-t" "--tag" TAGS "TAG" "Tag to apply (repeatable)"
#   args_positional "FILE" TARGET_FILE "File to operate on" required
#
#   args_parse "$@" || { rc=$?; exit "$(args_rc "$rc")"; }
#
# All declaration state is cleared after every args_parse call (success,
# failure, or help) so a run.sh may call this more than once per shell.
# This file never calls "exit" -- only "return" -- so it stays safe to use
# from scripts with "set -euo pipefail".

declare _ARGS_DESCRIPTION=""
declare -a _ARGS_EXAMPLES=()
declare -a _ARGS_OPT_SHORT=()
declare -a _ARGS_OPT_LONG=()
declare -a _ARGS_OPT_VAR=()
declare -a _ARGS_OPT_METAVAR=()
declare -a _ARGS_OPT_DESC=()
declare -a _ARGS_OPT_KIND=()
declare -a _ARGS_POS_NAME=()
declare -a _ARGS_POS_VAR=()
declare -a _ARGS_POS_DESC=()
declare -a _ARGS_POS_REQ=()

#shellcheck disable=SC2329
_args_clear_state() {
  _ARGS_DESCRIPTION=""
  _ARGS_EXAMPLES=()
  _ARGS_OPT_SHORT=()
  _ARGS_OPT_LONG=()
  _ARGS_OPT_VAR=()
  _ARGS_OPT_METAVAR=()
  _ARGS_OPT_DESC=()
  _ARGS_OPT_KIND=()
  _ARGS_POS_NAME=()
  _ARGS_POS_VAR=()
  _ARGS_POS_DESC=()
  _ARGS_POS_REQ=()
}

#shellcheck disable=SC2329
args_description() {
  _ARGS_DESCRIPTION="$1"
}

#shellcheck disable=SC2329
args_example() {
  _ARGS_EXAMPLES+=("$1")
}

# args_value SHORT LONG VAR METAVAR DESC
#shellcheck disable=SC2329
args_value() {
  _ARGS_OPT_SHORT+=("$1")
  _ARGS_OPT_LONG+=("$2")
  _ARGS_OPT_VAR+=("$3")
  _ARGS_OPT_METAVAR+=("$4")
  _ARGS_OPT_DESC+=("$5")
  _ARGS_OPT_KIND+=("value")
}

# args_flag SHORT LONG VAR DESC
#shellcheck disable=SC2329
args_flag() {
  _ARGS_OPT_SHORT+=("$1")
  _ARGS_OPT_LONG+=("$2")
  _ARGS_OPT_VAR+=("$3")
  _ARGS_OPT_METAVAR+=("")
  _ARGS_OPT_DESC+=("$4")
  _ARGS_OPT_KIND+=("flag")
}

# args_repeat SHORT LONG VAR METAVAR DESC
#shellcheck disable=SC2329
args_repeat() {
  _ARGS_OPT_SHORT+=("$1")
  _ARGS_OPT_LONG+=("$2")
  _ARGS_OPT_VAR+=("$3")
  _ARGS_OPT_METAVAR+=("$4")
  _ARGS_OPT_DESC+=("$5")
  _ARGS_OPT_KIND+=("repeat")
}

# args_positional NAME VAR DESC required|optional|rest
#shellcheck disable=SC2329
args_positional() {
  _ARGS_POS_NAME+=("$1")
  _ARGS_POS_VAR+=("$2")
  _ARGS_POS_DESC+=("$3")
  _ARGS_POS_REQ+=("$4")
}

#shellcheck disable=SC2329
args_show_help() {
  local pos_usage=""
  local i name req
  for i in "${!_ARGS_POS_NAME[@]}"; do
    name="${_ARGS_POS_NAME[$i]}"
    req="${_ARGS_POS_REQ[$i]}"
    case "$req" in
    required)
      pos_usage="$pos_usage $name"
      ;;
    optional)
      pos_usage="$pos_usage [$name]"
      ;;
    rest)
      pos_usage="$pos_usage [$name...]"
      ;;
    esac
  done

  echo "Usage: $(basename "$0") [OPTIONS]${pos_usage}"
  echo ""
  if [[ -n "$_ARGS_DESCRIPTION" ]]; then
    echo "$_ARGS_DESCRIPTION"
    echo ""
  fi

  echo "Options:"

  local -a rows=()
  local short long metavar desc flag_text
  for i in "${!_ARGS_OPT_SHORT[@]}"; do
    short="${_ARGS_OPT_SHORT[$i]}"
    long="${_ARGS_OPT_LONG[$i]}"
    metavar="${_ARGS_OPT_METAVAR[$i]}"
    desc="${_ARGS_OPT_DESC[$i]}"

    if [[ -n "$short" ]]; then
      flag_text="$short"
      if [[ -n "$long" ]]; then
        flag_text="$flag_text, $long"
      fi
    else
      flag_text="$long"
    fi
    if [[ -n "$metavar" ]]; then
      flag_text="$flag_text $metavar"
    fi

    rows+=("$flag_text"$'\t'"$desc")
  done
  rows+=("-h, --help"$'\t'"Show this help message and exit")

  local max_width=0 row len
  for row in "${rows[@]}"; do
    flag_text="${row%%$'\t'*}"
    len=${#flag_text}
    if [[ "$len" -gt "$max_width" ]]; then
      max_width="$len"
    fi
  done

  for row in "${rows[@]}"; do
    flag_text="${row%%$'\t'*}"
    desc="${row#*$'\t'}"
    printf '  %-*s  %s\n' "$max_width" "$flag_text" "$desc"
  done

  if [[ "${#_ARGS_POS_NAME[@]}" -gt 0 ]]; then
    echo ""
    echo "Positional arguments:"
    local pname pdesc
    for i in "${!_ARGS_POS_NAME[@]}"; do
      pname="${_ARGS_POS_NAME[$i]}"
      pdesc="${_ARGS_POS_DESC[$i]}"
      printf '  %-*s  %s\n' "$max_width" "$pname" "$pdesc"
    done
  fi

  if [[ "${#_ARGS_EXAMPLES[@]}" -gt 0 ]]; then
    echo ""
    echo "Examples:"
    local ex
    for ex in "${_ARGS_EXAMPLES[@]}"; do
      echo "  $ex"
    done
  fi
}

# args_rc RC
# Translate an args_parse return code into a process exit code: the
# synthetic "help was shown" code (64) becomes a clean 0, everything else
# passes through unchanged.
#shellcheck disable=SC2329
args_rc() {
  local rc="$1"
  if [[ "$rc" -eq 64 ]]; then
    echo 0
  else
    echo "$rc"
  fi
}

# args_parse "$@"
# Consumes declared options/positionals, assigning caller variables via
# namerefs. Returns 64 if -h/--help was handled (help already printed to
# stdout), 2 on any parse error (message already printed), 0 on success.
# Always clears declaration state before returning, regardless of outcome.
#shellcheck disable=SC2329
args_parse() {
  local -a positionals=()
  local double_dash_seen=false
  local arg opt_name opt_inline_value has_inline

  while [[ "$#" -gt 0 ]]; do
    arg="$1"

    if [[ "$double_dash_seen" == false && "$arg" == "--" ]]; then
      double_dash_seen=true
      shift
      continue
    fi

    if [[ "$double_dash_seen" == false ]] && { [[ "$arg" == "-h" ]] || [[ "$arg" == "--help" ]]; }; then
      args_show_help
      _args_clear_state
      return 64
    fi

    if [[ "$double_dash_seen" == false && "$arg" == -* ]]; then
      opt_name="$arg"
      opt_inline_value=""
      has_inline=false
      if [[ "$arg" == --*=* ]]; then
        opt_name="${arg%%=*}"
        opt_inline_value="${arg#*=}"
        has_inline=true
      fi

      local found=false idx kind varname value
      for idx in "${!_ARGS_OPT_SHORT[@]}"; do
        if { [[ -n "${_ARGS_OPT_SHORT[$idx]}" ]] && [[ "$opt_name" == "${_ARGS_OPT_SHORT[$idx]}" ]]; } ||
          { [[ -n "${_ARGS_OPT_LONG[$idx]}" ]] && [[ "$opt_name" == "${_ARGS_OPT_LONG[$idx]}" ]]; }; then
          found=true
          kind="${_ARGS_OPT_KIND[$idx]}"
          varname="${_ARGS_OPT_VAR[$idx]}"

          if [[ "$kind" == "flag" ]]; then
            local -n _args_ref="$varname"
            _args_ref=true
            unset -n _args_ref
            shift
          else
            if [[ "$has_inline" == true ]]; then
              value="$opt_inline_value"
              shift
            else
              if [[ "$#" -lt 2 ]]; then
                print_error "Missing value for option: $opt_name"
                echo "Use -h or --help for usage information"
                _args_clear_state
                return 2
              fi
              value="$2"
              shift 2
            fi

            if [[ "$kind" == "value" ]]; then
              local -n _args_ref="$varname"
              _args_ref="$value"
              unset -n _args_ref
            else
              local -n _args_ref="$varname"
              _args_ref+=("$value")
              unset -n _args_ref
            fi
          fi
          break
        fi
      done

      if [[ "$found" == false ]]; then
        print_error "Unknown option: $arg"
        echo "Use -h or --help for usage information"
        _args_clear_state
        return 2
      fi
    else
      positionals+=("$arg")
      shift
    fi
  done

  local n_pos="${#_ARGS_POS_NAME[@]}" n_given="${#positionals[@]}"
  local p_idx given_idx=0 pname pvar preq
  for ((p_idx = 0; p_idx < n_pos; p_idx += 1)); do
    pname="${_ARGS_POS_NAME[$p_idx]}"
    pvar="${_ARGS_POS_VAR[$p_idx]}"
    preq="${_ARGS_POS_REQ[$p_idx]}"

    if [[ "$preq" == "rest" ]]; then
      local -n _args_nameref="$pvar"
      _args_nameref=()
      while [[ "$given_idx" -lt "$n_given" ]]; do
        _args_nameref+=("${positionals[$given_idx]}")
        given_idx=$((given_idx + 1))
      done
      unset -n _args_nameref
    elif [[ "$given_idx" -lt "$n_given" ]]; then
      # shellcheck disable=SC2178
      local -n _args_nameref="$pvar"
      # shellcheck disable=SC2178
      _args_nameref="${positionals[$given_idx]}"
      unset -n _args_nameref
      given_idx=$((given_idx + 1))
    elif [[ "$preq" == "required" ]]; then
      print_error "Missing required argument: $pname"
      echo "Use -h or --help for usage information"
      _args_clear_state
      return 2
    fi
  done

  if [[ "$given_idx" -lt "$n_given" ]]; then
    print_error "Unexpected argument: ${positionals[$given_idx]}"
    echo "Use -h or --help for usage information"
    _args_clear_state
    return 2
  fi

  _args_clear_state
  return 0
}
