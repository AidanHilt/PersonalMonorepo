{ inputs, globals, pkgs, machine-config, ...}:

let
mono-flake-new-module = pkgs.writeShellScriptBin "mono-flake-new-module" ''
#!/bin/bash

set -euo pipefail

# Check if PERSONAL_MONOREPO_LOCATION is set
if [[ -z "$PERSONAL_MONOREPO_LOCATION" ]]; then
    echo "Error: PERSONAL_MONOREPO_LOCATION environment variable is not set"
    exit 1
fi

MODULES_DIR="$PERSONAL_MONOREPO_LOCATION/nix/mono-flake/modules"
TEMPLATE_FILE="$PERSONAL_MONOREPO_LOCATION/nix/mono-flake/templates/module.nix"

# Check if template file exists
if [[ ! -f "$TEMPLATE_FILE" ]]; then
    echo "Error: Template file not found at $TEMPLATE_FILE"
    exit 1
fi

# Check if modules directory exists
if [[ ! -d "$MODULES_DIR" ]]; then
    echo "Error: Modules directory not found at $MODULES_DIR"
    exit 1
fi

# Function to select directory interactively
select_directory() {
    echo "Available directories in $MODULES_DIR:"
    local dirs=()
    local i=1
    
    # Find all directories (including subdirectories)
    while IFS= read -r -d "" dir; do
        # Get relative path from modules directory
        rel_path="''${dir#$MODULES_DIR/}"
        dirs+=("$rel_path")
        echo "$i) $rel_path"
        ((i++))
    done < <(find "$MODULES_DIR" -type d -not -path "$MODULES_DIR" -print0 | sort -z)
    
    if [[ ''${#dirs[@]} -eq 0 ]]; then
        selected_dir="$PERSONAL_MONOREPO_LOCATION/nix/mono-flake/modules"
    else
        echo "$i) Create new directory"
        echo "0) Exit"
        
        read -p "Select directory (number): " choice
        
        if [[ "$choice" == "0" ]]; then
            echo "Exiting..."
            exit 0
        elif [[ "$choice" == "$i" ]]; then
            read -p "Enter new directory name: " new_dir
            selected_dir="$new_dir"
        elif [[ "$choice" =~ ^[0-9]+$ ]] && [[ "$choice" -ge 1 ]] && [[ "$choice" -lt "$i" ]]; then
            selected_dir="''${dirs[$((choice-1))]}"
        else
            echo "Invalid selection"
            exit 1
        fi
    fi
}

# Function to get module name
get_module_name() {
    read -p "Enter module name (without .nix extension): " module_name
    if [[ -z "$module_name" ]]; then
        echo "Error: Module name cannot be empty"
        exit 1
    fi
    
    # Remove .nix extension if provided
    module_name="''${module_name%.nix}"
}

# Parse command line arguments
module_path=""
while [[ $# -gt 0 ]]; do
    case $1 in
        --module-path)
            module_path="$2"
            shift 2
            break
            ;;
        --home-manager)
            module_path="$PERSONAL_MONOREPO_LOCATION/nix/mono-flake/home-manager/modules"
            shift 2
            break
            ;;
        *)
            echo "Unknown option: $1"
            echo "Usage: $0 [--module-path PATH] [--home-manager]"
            exit 1
            ;;
    esac
done

# If module path is provided, use it directly
if [[ -n "$module_path" ]]; then
    # Check if path is absolute or relative
    if [[ "$module_path" == /* ]]; then
        # Absolute path
        target_file="$module_path"
    else
        # Relative path - assume it's relative to modules directory
        target_file="$MODULES_DIR/$module_path"
    fi
    
    # Ensure .nix extension
    if [[ "$target_file" != *.nix ]]; then
        target_file="$target_file.nix"
    fi
else
    # Interactive mode
    echo "Interactive module creation"
    echo "=========================="
    
    select_directory
    get_module_name
    
    target_file="$MODULES_DIR/$selected_dir/$module_name.nix"
fi

# Create target directory if it doesn't exist
target_dir="$(dirname "$target_file")"
if [[ ! -d "$target_dir" ]]; then
    echo "Creating directory: $target_dir"
    mkdir -p "$target_dir"
fi

# Check if target file already exists
if [[ -f "$target_file" ]]; then
    read -p "File $target_file already exists. Overwrite? (y/N): " overwrite
    if [[ "$overwrite" != "y" && "$overwrite" != "Y" ]]; then
        echo "Operation cancelled"
        exit 0
    fi
fi

# Copy template to target location
echo "Copying template to: $target_file"
cp "$TEMPLATE_FILE" "$target_file"

echo "Module created successfully at: $target_file"
'';
in

{
  environment.systemPackages = [
    mono-flake-new-module
  ];
}