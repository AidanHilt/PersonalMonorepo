#!/bin/zsh

#ZSH script to add conditions to all templates in a helm repo

# Step 1: Take a directory as the first argument
directory=$1

# Step 2: Loop through all yaml files in <directory>/templates
for yaml_file in "${directory}"/templates/*.yaml; do
    # Extract the file basename without extension
    file_basename=${yaml_file:t:r}

    # Step 3: Prepend and append the condition for enabled flag
    sed -i '' "1s/^/{{ if .Values.${file_basename}.enabled }}\\
/" "${yaml_file}"
    echo "{{end}}" >> "${yaml_file}"
done
