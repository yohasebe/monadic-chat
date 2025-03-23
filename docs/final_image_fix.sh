#!/bin/bash

# Root directory of docs
DOCS_ROOT="/Users/yohasebe/code/monadic-chat/docs"

# Backup the current state
BACKUP_FILE="/Users/yohasebe/code/monadic-chat/docs_backup_$(date +%Y%m%d%H%M%S).tar.gz"
echo "Creating backup at $BACKUP_FILE"
cd /Users/yohasebe/code/monadic-chat
tar -czf "$BACKUP_FILE" docs/

# Function to calculate the relative path prefix based on directory depth
get_relative_path_prefix() {
    local dir="$1"
    local path_depth=$(echo "$dir" | sed "s#$DOCS_ROOT/##" | grep -o "/" | wc -l)
    local prefix=""
    
    # Root level files need ./
    if [ "$path_depth" -eq 0 ]; then
        prefix="./"
    else
        # Each subdirectory level needs an additional ../
        for ((i=0; i<$path_depth; i++)); do
            prefix="../$prefix"
        done
    fi
    
    echo "$prefix"
}

# Process all markdown files
find "$DOCS_ROOT" -type f -name "*.md" | while read -r file; do
    echo "Processing $file"
    dir=$(dirname "$file")
    relative_prefix=$(get_relative_path_prefix "$dir")
    
    # Create a temporary file
    temp_file="${file}.tmp"
    
    # Read the file line by line to preserve correct markdown
    while IFS= read -r line; do
        # Fix broken image links with missing parenthesis and incorrect slashes
        # For example: ![Chat app icon]..assets/icons/chat.png ':size=40')
        if [[ $line =~ \!\[.*\][.][.]+ ]]; then
            # Extract image description
            desc=$(echo "$line" | sed -E 's/\!\[(.*)\].*/\1/')
            
            # Extract image path and attributes
            path_attr=$(echo "$line" | sed -E 's/\!\[.*\](.*)/\1/')
            
            # If missing opening parenthesis, extract path correctly
            if [[ ! $path_attr =~ ^\( ]]; then
                path_attr=$(echo "$line" | sed -E 's/\!\[.*\]([^(].*)/\1/')
            fi
            
            # Fix path with proper relative path prefix
            if [[ "$relative_prefix" == "./" ]]; then
                # Root level
                if [[ $path_attr =~ ^[.][.]/assets/ ]]; then
                    path_attr="${path_attr/..\/assets\//assets\/}"
                elif [[ $path_attr =~ ^[.][.][.][.]/assets/ ]]; then
                    path_attr="${path_attr/....\/assets\//assets\/}"
                elif [[ $path_attr =~ ^[.][.]/[.][.]/assets/ ]]; then
                    path_attr="${path_attr/..\/..\/assets\//assets\/}"
                elif [[ $path_attr =~ ^[.][.][.][.]/[.][.]/assets/ ]]; then
                    path_attr="${path_attr/..\/..\/..\/assets\//assets\/}"
                elif [[ $path_attr =~ ^assets/ ]]; then
                    # Already correct
                    :
                else
                    # Use basic fix if not matching any pattern
                    path_attr=$(echo "$path_attr" | sed -E 's/\.\.+assets\//assets\//g')
                fi
            else
                # Subdirectory level
                if [[ $path_attr =~ ^[.][.]+assets/ ]]; then
                    # Fix paths like ..assets/ -> ../assets/
                    path_attr=$(echo "$path_attr" | sed -E 's/\.\.+assets\//..\/assets\//g')
                    path_attr=$(echo "$path_attr" | sed -E 's/\.\.\/\.\.+assets\//..\/..\/assets\//g')
                elif [[ $path_attr =~ ^assets/ ]]; then
                    # Convert assets/ to ../assets/ for subdirectories
                    path_attr="${relative_prefix}${path_attr}"
                fi
            fi
            
            # Ensure proper Markdown syntax
            if [[ ! $path_attr =~ ^\( ]]; then
                path_attr="($path_attr"
            fi
            
            if [[ ! $path_attr =~ \)$ && $path_attr =~ \'size ]]; then
                path_attr="${path_attr})"
            fi
            
            # Reconstruct the line
            line="![${desc}]${path_attr}"
        fi
        
        # Output the fixed line to the temporary file
        echo "$line" >> "$temp_file"
    done < "$file"
    
    # Replace the original file with the fixed file
    mv "$temp_file" "$file"
done

echo "Image paths have been fixed!"