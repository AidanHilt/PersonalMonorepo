{ inputs, globals, pkgs, machine-config, lib, ...}:

let
context-list-scripts = pkgs.writeShellScriptBin "context-list-scripts" ''
#!/bin/bash

set -euo pipefail

if [[ ! -v ATILS_CURRENT_CONTEXT ]]; then
  echo "No context is currently activated. Please activate one using 'context-activate-context'"
  exit 1
fi

# Function to extract first comment line from a file
get_description() {
  local file="$1"
  local first_line

  # Read first line
  first_line=$(head -n 1 "$file" 2>/dev/null || echo "")

  # Check if it starts with shebang, if so get second line
  if [[ "$first_line" =~ ^#! ]]; then
    first_line=$(sed -n '2p' "$file" 2>/dev/null || echo "")
  fi

  # If it's a comment, extract the description
  if [[ "$first_line" =~ ^#[[:space:]]*(.*) ]]; then
    echo "''${BASH_REMATCH[1]}"
  else
    echo ""
  fi
}

# Function to check if file is executable
is_executable() {
  [[ -x "$1" && -f "$1" ]]
}

# Function to get file type/language hint
get_file_type() {
  local file="$1"
  local first_line

  first_line=$(head -n 1 "$file" 2>/dev/null || echo "")

  case "$first_line" in
    "#!/bin/bash"*|"#!/usr/bin/bash"*) echo "bash" ;;
    "#!/bin/sh"*|"#!/usr/bin/sh"*) echo "sh" ;;
    "#!/usr/bin/env bash"*) echo "bash" ;;
    "#!/usr/bin/env sh"*) echo "sh" ;;
    "#!/usr/bin/env python"*) echo "python" ;;
    "#!/usr/bin/python"*) echo "python" ;;
    "#!/usr/bin/env node"*) echo "node" ;;
    "#!/usr/bin/env ruby"*) echo "ruby" ;;
    "#!/bin/zsh"*|"#!/usr/bin/zsh"*) echo "zsh" ;;
    *) echo "" ;;
  esac
}

# Colors for pretty printing
if [[ -t 1 ]]; then  # Only use colors if stdout is a terminal
  readonly RED='\033[0;31m'
  readonly GREEN='\033[0;32m'
  readonly YELLOW='\033[0;33m'
  readonly BLUE='\033[0;34m'
  readonly PURPLE='\033[0;35m'
  readonly CYAN='\033[0;36m'
  readonly GRAY='\033[0;37m'
  readonly BOLD='\033[1m'
  readonly NC='\033[0m'  # No Color
else
  readonly RED=""
  readonly GREEN=""
  readonly YELLOW=""
  readonly BLUE=""
  readonly PURPLE=""
  readonly CYAN=""
  readonly GRAY=""
  readonly BOLD=""
  readonly NC=""
fi

# Header
echo -e "''${BOLD}Scripts for context ''${BLUE}"''$ATILS_CURRENT_CONTEXT"''${NC}''${BOLD}:''${NC}"
echo

if [[ -d "$ATILS_CURRENT_CONTEXT_SCRIPTS_DIR" ]]; then
  files_found=0
  declare -a script_info

  while IFS= read -r -d "" file; do
    filename=''$(basename "$file")

    # Skip hidden files and common non-script files
    [[ "$filename" =~ ^\. ]] && continue
    [[ "$filename" =~ \.(txt|md|json|yml|yaml|xml)$ ]] && continue

    if is_executable "$file"; then
      description=$(get_description "$file")
      file_type=$(get_file_type "$file")
      script_info+=("$filename|$description|$file_type")
      ((files_found++))
    fi
  done < <(find "$ATILS_CURRENT_CONTEXT_SCRIPTS_DIR" -maxdepth 1 -type f -print0 | sort -z)
else
  echo -e "''${GRAY}No scripts directory found.''${NC}"
  exit 0
fi

# Calculate column widths for alignment
max_name_length=0
max_type_length=0

for info in "''${script_info[@]}"; do
  IFS='|' read -r name desc type <<< "$info"
  [[ ''${#name} -gt $max_name_length ]] && max_name_length=''${#name}
  [[ ''${#type} -gt $max_type_length ]] && max_type_length=''${#type}
done

# Add some padding
((max_name_length += 2))
((max_type_length += 2))

# Print scripts with descriptions
for info in "''${script_info[@]}"; do
  IFS='|' read -r name desc type <<< "$info"

  # Color the file type
  colored_type=""
  if [[ -n "$type" ]]; then
    case "$type" in
      bash|sh) colored_type="''${GREEN}[$type]''${NC}" ;;
      python) colored_type="''${YELLOW}[$type]''${NC}" ;;
      node) colored_type="''${CYAN}[$type]''${NC}" ;;
      ruby) colored_type="''${RED}[$type]''${NC}" ;;
      zsh) colored_type="''${PURPLE}[$type]''${NC}" ;;
      *) colored_type="''${GRAY}[$type]''${NC}" ;;
    esac
  fi

  # Format the line
  printf "  ''${BOLD}%-''${max_name_length}s''${NC}" "$name"

  if [[ -n "$colored_type" ]]; then
    printf " %-$((max_type_length + 9))s" "$colored_type"  # +9 for color codes
  else
    printf " %-''${max_type_length}s" ""
  fi

  if [[ -n "$desc" ]]; then
    echo -e "''${GRAY}$desc''${NC}"
  else
    echo
  fi
done
'';
in

{
  environment.systemPackages = [
  context-list-scripts
  ];
}