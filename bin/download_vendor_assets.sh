#!/bin/bash
# Script to download third-party libraries for local use

# Load the shared assets configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ASSETS_LIST_PATH="${SCRIPT_DIR}/../docker/services/ruby/bin/assets_list.sh"
source "${ASSETS_LIST_PATH}"

# Set base path for the project
BASE_PATH="$(pwd)"
VENDOR_PATH="${BASE_PATH}/docker/services/ruby/public/vendor"

# Create necessary directories
mkdir -p "${VENDOR_PATH}/css"
mkdir -p "${VENDOR_PATH}/js"
mkdir -p "${VENDOR_PATH}/fonts"
mkdir -p "${VENDOR_PATH}/webfonts"

# Define a function to download files
download_file() {
  url="$1"
  destination="$2"
  
  echo "Downloading: $url to $destination"
  if [ -f "$destination" ]; then
    echo "File already exists: $destination"
    return 0
  fi
  
  curl -L --silent "$url" -o "$destination"
  if [ $? -eq 0 ]; then
    echo "Downloaded successfully: $destination"
  else
    echo "Failed to download: $url"
    exit 1
  fi
}

# Process assets from the shared configuration
for asset in "${ASSETS[@]}"; do
  # Split the entry into type, url, and filename
  IFS=',' read -r type url filename <<< "$asset"
  
  # Determine the destination path based on the asset type
  case "$type" in
    css)
      dest="${VENDOR_PATH}/css/${filename}"
      ;;
    js)
      dest="${VENDOR_PATH}/js/${filename}"
      ;;
    font)
      dest="${VENDOR_PATH}/fonts/${filename}"
      ;;
    webfont)
      dest="${VENDOR_PATH}/webfonts/${filename}"
      ;;
    *)
      echo "Unknown asset type: $type" >&2
      continue
      ;;
  esac
  
  # Download the file
  download_file "$url" "$dest"
done

# Fix Font Awesome webfont paths in the CSS file
if [ -f "${VENDOR_PATH}/css/all.min.css" ]; then
  echo "Fixing Font Awesome webfont paths in CSS file..."
  # Use different sed syntax for macOS vs Linux
  if [[ "$OSTYPE" == "darwin"* ]]; then
    # macOS version
    sed -i '' 's|url("../webfonts/|url("/vendor/webfonts/|g' "${VENDOR_PATH}/css/all.min.css"
  else
    # Linux version
    sed -i 's|url("../webfonts/|url("/vendor/webfonts/|g' "${VENDOR_PATH}/css/all.min.css"
  fi
  echo "Font Awesome paths fixed successfully"
fi

# Create a CSS file for local Montserrat font
echo "Creating Montserrat CSS file..."
echo "$MONTSERRAT_CSS" > "${VENDOR_PATH}/css/montserrat.css"

echo "All vendor files have been downloaded"
echo "These files will be available for both development and production use"