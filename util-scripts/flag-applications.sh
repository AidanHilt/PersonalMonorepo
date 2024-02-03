#!/bin/zsh

#ZSH script to grab all templates in a helm chart, and give them a feature flag in values.yaml

# Step 1: Take a directory as the first argument
directory=$1

# Create the output file if it doesn't exist
output_file="${directory}/values.yaml"
touch "${output_file}"

# Step 2: Loop through all yaml files in <directory>/templates
for yaml_file in "${directory}"/templates/*.yaml; do
    # Extract the file basename without extension
    file_basename=${yaml_file:t:r}

    # Step 3: Use yq to construct a snippet and append it to the output file
    snippet="${file_basename}: enabled: true"
    if grep -q "^${file_basename}:" "${output_file}"; then
        # If the file_basename exists in the output_file, replace the existing line with the new snippet
        sed -i '' "/^${file_basename}:/ c\\
${snippet}" "${output_file}"
    else
        # If the file_basename doesn't exist in the output_file, append the new snippet
        echo "${snippet}" >> "${output_file}"
    fi
done
