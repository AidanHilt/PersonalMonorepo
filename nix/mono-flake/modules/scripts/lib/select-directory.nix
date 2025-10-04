{ inputs, globals, pkgs, machine-config, lib, ...}:

let

  select-directory = pkgs.writeText "select-directory.sh" ''
    select-directory () {
      echo "Available directories in $OUTPUT_DIR:"
      local dirs=()
      local i=1

      # Find all directories (including subdirectories)
      while IFS= read -r -d "" dir; do
        # Get relative path from modules directory
        rel_path="''${dir#$OUTPUT_DIR/}"
        dirs+=("$rel_path")
        echo "$i) $rel_path"
        ((i++))
      done < <(find "$OUTPUT_DIR" -type d -not -path "$OUTPUT_DIR" -print0 | sort -z)

      if [[ ''${#dirs[@]} -eq 0 ]]; then
        SELECTED_DIR="$OUTPUT_DIR"
      else
        echo "$i) Create new directory"
        echo "0) Exit"

        read -p "Select directory (number): " choice

        if [[ "$choice" == "0" ]]; then
          echo "Exiting..."
          exit 0
        elif [[ "$choice" == "$i" ]]; then
          read -p "Enter new directory name: " new_dir
          SELECTED_DIR="$new_dir"
        elif [[ "$choice" =~ ^[0-9]+$ ]] && [[ "$choice" -ge 1 ]] && [[ "$choice" -lt "$i" ]]; then
          SELECTED_DIR="''${dirs[$((choice-1))]}"
        else
          echo "Invalid selection"
          exit 1
        fi
      fi
    }
  '';
in

{
  select-directory = select-directory;
}