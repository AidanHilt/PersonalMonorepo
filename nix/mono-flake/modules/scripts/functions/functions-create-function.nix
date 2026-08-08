{ inputs, globals, pkgs, machine-config, lib, ...}:

let
printing-and-output = import ../lib/_printing-and-output.nix { inherit pkgs; };

functions-create-function = pkgs.writeShellScriptBin "functions-create-function" ''
#!/bin/bash

set -euo pipefail

source ${printing-and-output.printing-and-output}

readonly FUNC_RUNTIME="go"
readonly GHCR_REGISTRY="''${GHCR_REGISTRY:-ghcr.io/your-org}"
readonly FUNCTIONS_ROOT="''${PERSONAL_MONOREPO_LOCATION}/functions"
readonly EVENTING_FILE_NAME="eventing.yaml"
readonly HTTP_TEMPLATE="http"
readonly CLOUDEVENTS_TEMPLATE="cloudevents"
readonly DEFAULT_NAMESPACE="default"
readonly DEFAULT_SCALE_MIN="0"
readonly DEFAULT_SCALE_MAX="10"
readonly FUNCTION_NAME_PATTERN="^[a-z]([-a-z0-9]*[a-z0-9])?$"
readonly CRON_FIELD_PATTERN="^[0-9*/,-]+$"

get_named_arg() {
  local FLAG_NAME="$1"
  local DEFAULT_VALUE="$2"
  shift 2
  local arg
  for arg in "$@"; do
    if [[ "''${arg}" == "--''${FLAG_NAME}="* ]]; then
      echo "''${arg#*=}"
      return 0
    fi
  done
  echo "''${DEFAULT_VALUE}"
}

prompt_with_default() {
  local PROMPT_TEXT="$1"
  shift
  local DEFAULT_VALUE
  DEFAULT_VALUE=$(get_named_arg "default" "" "$@")
  local USER_INPUT
  read -r -p "''${PROMPT_TEXT} [''${DEFAULT_VALUE}]: " USER_INPUT
  if [[ -z "''${USER_INPUT}" ]]; then
    echo "''${DEFAULT_VALUE}"
  else
    echo "''${USER_INPUT}"
  fi
}

prompt_required() {
  local PROMPT_TEXT="$1"
  local user_input
  while true; do
    read -r -p "''${PROMPT_TEXT}: " user_input
    if [[ -n "''${user_input}" ]]; then
      echo "''${user_input}"
      return 0
    fi
    print_error "A value is required."
  done
}

confirm_yes_no() {
  local PROMPT_TEXT="$1"
  shift
  local DEFAULT_VALUE
  DEFAULT_VALUE=$(get_named_arg "default" "n" "$@")
  local RAW_INPUT
  read -r -p "''${PROMPT_TEXT} (y/n) [''${DEFAULT_VALUE}]: " RAW_INPUT
  local RESOLVED_INPUT="''${RAW_INPUT:-''${DEFAULT_VALUE}}"
  [[ "''${RESOLVED_INPUT}" =~ ^[Yy]$ ]]
}

validate_function_name() {
  local CANDIDATE="$1"
  if [[ ! "''${CANDIDATE}" =~ ''${FUNCTION_NAME_PATTERN} ]]; then
    return 1
  fi
  if [[ "''${#CANDIDATE}" -gt 63 ]]; then
    return 1
  fi
  return 0
}

validate_cron_schedule() {
  local CANDIDATE="$1"
  local field
  local field_count=0
  for field in ''${CANDIDATE}; do
    field_count=$((field_count + 1))
    if [[ ! "''${field}" =~ ''${CRON_FIELD_PATTERN} ]]; then
      return 1
    fi
  done
  [[ "''${field_count}" -eq 5 ]]
}

collect_function_name() {
  print_debug "Prompting for function name."
  local candidate
  while true; do
    candidate=$(prompt_required "Function name")
    if validate_function_name "''${candidate}"; then
      echo "''${candidate}"
      return 0
    fi
    print_error "Function name must be a lowercase RFC1123 label (alphanumeric and hyphens, max 63 chars)."
  done
}

collect_invocation_source() {
  print_debug "Prompting for invocation source."
  local choice
  while true; do
    read -r -p "Invocation source (cron/http/cloudevent): " choice
    case "''${choice}" in
      cron|http|cloudevent)
        echo "''${choice}"
        return 0
        ;;
      *)
        print_error "Invocation source must be one of: cron, http, cloudevent."
        ;;
    esac
  done
}

collect_cron_schedule() {
  local candidate
  while true; do
    candidate=$(prompt_required "Cron schedule (5-field cron expression)")
    if validate_cron_schedule "''${candidate}"; then
      echo "''${candidate}"
      return 0
    fi
    print_error "Cron schedule must be a standard 5-field cron expression."
  done
}

collect_cron_data() {
  prompt_with_default "Cron event data payload" --default='{}'
}

collect_cron_content_type() {
  prompt_with_default "Cron event content type" --default="application/json"
}

collect_cron_trigger_name() {
  local FUNCTION_NAME="$1"
  prompt_with_default "PingSource name" --default="''${FUNCTION_NAME}-cron"
}

collect_cloudevent_broker() {
  prompt_with_default "Broker name" --default="default"
}

collect_cloudevent_trigger_name() {
  local FUNCTION_NAME="$1"
  prompt_with_default "Trigger name" --default="''${FUNCTION_NAME}-trigger"
}

collect_cloudevent_filters() {
  print_debug "Prompting for cloudevent filter attributes."
  local filters=""
  local filter_input
  while true; do
    read -r -p "Filter attribute as key=value (or blank to finish): " filter_input
    if [[ -z "''${filter_input}" ]]; then
      break
    fi
    if [[ -z "''${filters}" ]]; then
      filters="''${filter_input}"
    else
      filters="''${filters}"$'\n'"''${filter_input}"
    fi
  done
  echo "''${filters}"
}

collect_namespace() {
  prompt_with_default "Deploy namespace" --default="''${DEFAULT_NAMESPACE}"
}

collect_scale_min() {
  prompt_with_default "Minimum replicas" --default="''${DEFAULT_SCALE_MIN}"
}

collect_scale_max() {
  prompt_with_default "Maximum replicas" --default="''${DEFAULT_SCALE_MAX}"
}

collect_env_vars() {
  print_debug "Prompting for runtime environment variables."
  local env_vars=""
  local env_input
  while true; do
    read -r -p "Environment variable as KEY=VALUE (or blank to finish): " env_input
    if [[ -z "''${env_input}" ]]; then
      break
    fi
    if [[ -z "''${env_vars}" ]]; then
      env_vars="''${env_input}"
    else
      env_vars="''${env_vars}"$'\n'"''${env_input}"
    fi
  done
  echo "''${env_vars}"
}

collect_labels() {
  print_debug "Prompting for labels."
  local labels=""
  local label_input
  while true; do
    read -r -p "Label as KEY=VALUE (or blank to finish): " label_input
    if [[ -z "''${label_input}" ]]; then
      break
    fi
    if [[ -z "''${labels}" ]]; then
      labels="''${label_input}"
    else
      labels="''${labels}"$'\n'"''${label_input}"
    fi
  done
  echo "''${labels}"
}

resolve_func_template() {
  local INVOCATION_SOURCE="$1"
  case "''${INVOCATION_SOURCE}" in
    http)
      echo "''${HTTP_TEMPLATE}"
      ;;
    cron|cloudevent)
      echo "''${CLOUDEVENTS_TEMPLATE}"
      ;;
  esac
}

build_func_yaml_patch() {
  local FUNCTION_NAME NAMESPACE SCALE_MIN SCALE_MAX ENV_VARS LABELS

  FUNCTION_NAME=$(get_named_arg "function-name" "" "$@")
  NAMESPACE=$(get_named_arg "namespace" "''${DEFAULT_NAMESPACE}" "$@")
  SCALE_MIN=$(get_named_arg "scale-min" "''${DEFAULT_SCALE_MIN}" "$@")
  SCALE_MAX=$(get_named_arg "scale-max" "''${DEFAULT_SCALE_MAX}" "$@")
  ENV_VARS=$(get_named_arg "env-vars" "" "$@")
  LABELS=$(get_named_arg "labels" "" "$@")

  echo "registry: ''${GHCR_REGISTRY}"
  echo "image: ''${GHCR_REGISTRY}/''${FUNCTION_NAME}:latest"
  echo "deploy:"
  echo "  namespace: ''${NAMESPACE}"
  echo "  options:"
  echo "    scale:"
  echo "      min: ''${SCALE_MIN}"
  echo "      max: ''${SCALE_MAX}"
  if [[ -n "''${ENV_VARS}" ]]; then
    echo "envs:"
    while IFS='=' read -r env_key env_value; do
      echo "  - name: ''${env_key}"
      echo "    value: \"''${env_value}\""
    done <<< "''${ENV_VARS}"
  fi
  if [[ -n "''${LABELS}" ]]; then
    echo "labels:"
    while IFS='=' read -r label_key label_value; do
      echo "  ''${label_key}: \"''${label_value}\""
    done <<< "''${LABELS}"
  fi
}

build_eventing_yaml() {
  local FUNCTION_NAME INVOCATION_SOURCE CRON_SCHEDULE CRON_DATA CRON_CONTENT_TYPE CRON_TRIGGER_NAME
  local CLOUDEVENT_BROKER CLOUDEVENT_TRIGGER_NAME CLOUDEVENT_FILTERS

  FUNCTION_NAME=$(get_named_arg "function-name" "" "$@")
  INVOCATION_SOURCE=$(get_named_arg "invocation-source" "" "$@")
  CRON_SCHEDULE=$(get_named_arg "cron-schedule" "" "$@")
  CRON_DATA=$(get_named_arg "cron-data" "" "$@")
  CRON_CONTENT_TYPE=$(get_named_arg "cron-content-type" "" "$@")
  CRON_TRIGGER_NAME=$(get_named_arg "cron-trigger-name" "" "$@")
  CLOUDEVENT_BROKER=$(get_named_arg "cloudevent-broker" "" "$@")
  CLOUDEVENT_TRIGGER_NAME=$(get_named_arg "cloudevent-trigger-name" "" "$@")
  CLOUDEVENT_FILTERS=$(get_named_arg "cloudevent-filters" "" "$@")

  echo "apiVersion: v1"
  echo "function: ''${FUNCTION_NAME}"
  echo "trigger:"
  echo "  type: ''${INVOCATION_SOURCE}"
  case "''${INVOCATION_SOURCE}" in
    cron)
      echo "  cron:"
      echo "    name: ''${CRON_TRIGGER_NAME}"
      echo "    schedule: \"''${CRON_SCHEDULE}\""
      echo "    data: \"''${CRON_DATA}\""
      echo "    contentType: ''${CRON_CONTENT_TYPE}"
      ;;
    cloudevent)
      echo "  cloudevent:"
      echo "    name: ''${CLOUDEVENT_TRIGGER_NAME}"
      echo "    broker: ''${CLOUDEVENT_BROKER}"
      if [[ -n "''${CLOUDEVENT_FILTERS}" ]]; then
        echo "    filters:"
        while IFS= read -r filter_line; do
          echo "      - ''${filter_line}"
        done <<< "''${CLOUDEVENT_FILTERS}"
      fi
      ;;
  esac
}

ensure_functions_root() {
  print_debug "Ensuring ''${FUNCTIONS_ROOT} exists."
  mkdir -p "''${FUNCTIONS_ROOT}"
}

run_func_create() {
  local TARGET_DIR="$1"
  local TEMPLATE="$2"
  print_debug "Running func create for ''${TARGET_DIR} using template ''${TEMPLATE}."
  if ! func create -l "''${FUNC_RUNTIME}" -t "''${TEMPLATE}" "''${TARGET_DIR}"; then
    print_error "func create failed for ''${TARGET_DIR}."
    return 1
  fi
  print_debug "func create completed for ''${TARGET_DIR}."
  return 0
}

patch_func_yaml() {
  local TARGET_DIR="$1"
  local PATCH_CONTENT="$2"
  local FUNC_YAML_PATH="''${TARGET_DIR}/func.yaml"
  local PATCH_PATH="''${TARGET_DIR}/.func.yaml.patch"

  echo "''${PATCH_CONTENT}" > "''${PATCH_PATH}"
  print_debug "Merging generated patch into ''${FUNC_YAML_PATH}."
  if ! yq eval-all 'select(fileIndex==0) * select(fileIndex==1)' "''${FUNC_YAML_PATH}" "''${PATCH_PATH}" > "''${FUNC_YAML_PATH}.merged"; then
    print_error "Failed to merge func.yaml patch."
    rm -f "''${PATCH_PATH}"
    return 1
  fi
  mv "''${FUNC_YAML_PATH}.merged" "''${FUNC_YAML_PATH}"
  rm -f "''${PATCH_PATH}"
  print_debug "func.yaml updated."
  return 0
}

write_eventing_file() {
  local TARGET_DIR="$1"
  local EVENTING_CONTENT="$2"
  local EVENTING_PATH="''${TARGET_DIR}/''${EVENTING_FILE_NAME}"
  echo "''${EVENTING_CONTENT}" > "''${EVENTING_PATH}"
  print_debug "Wrote ''${EVENTING_PATH}."
}

main() {
  print_debug "Starting Knative function creation wizard."

  local FUNCTION_NAME
  FUNCTION_NAME=$(collect_function_name)

  local INVOCATION_SOURCE
  INVOCATION_SOURCE=$(collect_invocation_source)

  local CRON_SCHEDULE="" CRON_DATA="" CRON_CONTENT_TYPE="" CRON_TRIGGER_NAME=""
  local CLOUDEVENT_BROKER="" CLOUDEVENT_TRIGGER_NAME="" CLOUDEVENT_FILTERS=""

  case "''${INVOCATION_SOURCE}" in
    cron)
      print_debug "Collecting cron trigger details."
      CRON_SCHEDULE=$(collect_cron_schedule)
      CRON_DATA=$(collect_cron_data)
      CRON_CONTENT_TYPE=$(collect_cron_content_type)
      CRON_TRIGGER_NAME=$(collect_cron_trigger_name "''${FUNCTION_NAME}")
      ;;
    cloudevent)
      print_warning "Cloudevent trigger generation is not yet implemented by the reconciler; intent will be recorded only."
      CLOUDEVENT_BROKER=$(collect_cloudevent_broker)
      CLOUDEVENT_TRIGGER_NAME=$(collect_cloudevent_trigger_name "''${FUNCTION_NAME}")
      CLOUDEVENT_FILTERS=$(collect_cloudevent_filters)
      ;;
  esac

  print_debug "Collecting deploy configuration."
  local NAMESPACE SCALE_MIN SCALE_MAX ENV_VARS LABELS
  NAMESPACE=$(collect_namespace)
  SCALE_MIN=$(collect_scale_min)
  SCALE_MAX=$(collect_scale_max)
  ENV_VARS=$(collect_env_vars)
  LABELS=$(collect_labels)

  local FUNCTION_DIR="''${FUNCTIONS_ROOT}/''${FUNCTION_NAME}"

  echo ""
  echo "Function name:       ''${FUNCTION_NAME}"
  echo "Runtime:             ''${FUNC_RUNTIME}"
  echo "Invocation source:   ''${INVOCATION_SOURCE}"
  echo "Target directory:    ''${FUNCTION_DIR}"
  echo "Namespace:           ''${NAMESPACE}"
  echo "Scale:               min=''${SCALE_MIN} max=''${SCALE_MAX}"
  if [[ -n "''${ENV_VARS}" ]]; then
    echo "Environment variables:"
    echo "''${ENV_VARS}"
  fi
  if [[ -n "''${LABELS}" ]]; then
    echo "Labels:"
    echo "''${LABELS}"
  fi
  echo ""

  if ! confirm_yes_no "Create this function" --default="y"; then
    print_debug "User declined to proceed."
    return 1
  fi

  local FUNC_TEMPLATE
  FUNC_TEMPLATE=$(resolve_func_template "''${INVOCATION_SOURCE}")

  ensure_functions_root

  if ! run_func_create "''${FUNCTION_DIR}" "''${FUNC_TEMPLATE}"; then
    return 1
  fi

  local PATCH_CONTENT
  PATCH_CONTENT=$(build_func_yaml_patch --function-name="''${FUNCTION_NAME}" --namespace="''${NAMESPACE}" --scale-min="''${SCALE_MIN}" --scale-max="''${SCALE_MAX}" --env-vars="''${ENV_VARS}" --labels="''${LABELS}")

  if ! patch_func_yaml "''${FUNCTION_DIR}" "''${PATCH_CONTENT}"; then
    return 1
  fi

  local EVENTING_CONTENT
  EVENTING_CONTENT=$(build_eventing_yaml --function-name="''${FUNCTION_NAME}" --invocation-source="''${INVOCATION_SOURCE}" --cron-schedule="''${CRON_SCHEDULE}" --cron-data="''${CRON_DATA}" --cron-content-type="''${CRON_CONTENT_TYPE}" --cron-trigger-name="''${CRON_TRIGGER_NAME}" --cloudevent-broker="''${CLOUDEVENT_BROKER}" --cloudevent-trigger-name="''${CLOUDEVENT_TRIGGER_NAME}" --cloudevent-filters="''${CLOUDEVENT_FILTERS}")

  write_eventing_file "''${FUNCTION_DIR}" "''${EVENTING_CONTENT}"

  print_status "Function ''${FUNCTION_NAME} created successfully at ''${FUNCTION_DIR}."
  return 0
}

main "$@"
'';
in

{
  environment.systemPackages = [
    functions-create-function
  ];
}