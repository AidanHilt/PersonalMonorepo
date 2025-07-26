{ inputs, globals, pkgs, machine-config, lib, ...}:

let
_modify-secrets-nix-let-statement = pkgs.writeShellScriptBin "_modify-secrets-nix-let-statement" ''
#!/bin/bash

set -euo pipefail

# Check if we have exactly 3 arguments
if [ $# -ne 3 ]; then
    echo "Usage: $0 <filename> <key> <value>"
    echo "Example: $0 secrets.nix apiKey '\"new-api-key\"'"
    exit 1
fi

filename="$1"
key="$2"
value="$3"

# Check if the file exists
if [ ! -f "$filename" ]; then
    echo "Error: File '$filename' does not exist."
    exit 1
fi

# Find line numbers for "let" and "in"
let_line=$(grep -n "^[[:space:]]*let[[:space:]]*$" "$filename" | head -1 | cut -d: -f1)
in_line=$(grep -n "^[[:space:]]*in[[:space:]]*$" "$filename" | head -1 | cut -d: -f1)

# Check if we found both "let" and "in"
if [ -z "$let_line" ]; then
    echo "Error: Could not find 'let' statement on its own line in '$filename'"
    exit 1
fi

if [ -z "$in_line" ]; then
    echo "Error: Could not find 'in' statement on its own line in '$filename'"
    exit 1
fi

echo "Found 'let' at line $let_line and 'in' at line $in_line"

# Create a temporary file
temp_file=$(mktemp)

# Check if the key already exists between let and in lines
key_line=$(sed -n "''${let_line},''${in_line}p" "$filename" | grep -n "^[[:space:]]*$key[[:space:]]*=" | head -1 | cut -d: -f1 || true)

if [ -n "$key_line" ]; then
    # Key exists - calculate actual line number and update it
    actual_key_line=$((let_line + key_line - 1))
    echo "Key '$key' found at line $actual_key_line - updating..."
    
    # Update the existing key
    sed "s/^[[:space:]]*''${key}[[:space:]]*=.*/''${key} = ''${value};/" "$filename" > "$temp_file"
else
    # Key doesn't exist - add it before the "in" line
    echo "Key '$key' not found - adding new entry..."
    
    # Get the indentation of the "in" line to match it
    in_indent=$(sed -n "''${in_line}p" "$filename" | sed 's/\(^[[:space:]]*\).*/\1/')
    
    # Add the new key-value pair with a blank line before "in"
    {
        # Print everything up to (but not including) the "in" line
        head -n $((in_line - 1)) "$filename"
        
        # Add the new key-value pair with proper indentation
        echo "''${in_indent}''${key} = ''${value};"
        
        # Add blank line for separation
        echo ""
        
        # Print the "in" line and everything after
        tail -n +''${in_line} "$filename"
    } > "$temp_file"
fi

# Replace the original file with the modified version
if mv "$temp_file" "$filename"; then
    echo "Successfully updated '$filename'"
else
    echo "Error: Failed to update '$filename'"
    rm -f "$temp_file"
    exit 1
fi
'';
in

{
  environment.systemPackages = [
    _modify-secrets-nix-let-statement
  ];
}