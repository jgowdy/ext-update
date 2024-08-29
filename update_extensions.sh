#!/bin/bash

# Ensure jq and xmllint are installed
if ! command -v jq &> /dev/null
then
    echo "jq is required but not installed. Please install jq using 'brew install jq' and run this script again."
    exit 1
fi

if ! command -v xmllint &> /dev/null
then
    echo "xmllint is required but not installed. Please install xmllint using 'brew install libxml2' and run this script again."
    exit 1
fi

# Initialize force update flag
force_update=false

# Check for -f option
while getopts "f" opt; do
    case $opt in
        f)
            force_update=true
            ;;
        *)
            echo "Usage: $0 [-f]"
            exit 1
            ;;
    esac
done

# Function to unpack a zip file and move contents correctly
unpack_zip() {
    zip_file=$1
    base_name="${zip_file%-master.zip}"
    output_dir="${base_name%-*}"
    temp_dir="${base_name}-temp"

    rm -rf "$output_dir"
    rm -rf "$temp_dir"
    mkdir -p "$temp_dir"
    unzip -qq "$zip_file" -d "$temp_dir"

    # Find the inner directory and move its contents to the output directory
    inner_dir=$(find "$temp_dir" -mindepth 1 -maxdepth 1 -type d)
    if [[ -d "$inner_dir" ]]; then
        mkdir -p "$output_dir"
        mv "$inner_dir"/* "$output_dir"
    else
        echo "No directory found inside the ZIP file"
    fi
    rm -rf "$temp_dir"

    echo "Unpacked $zip_file to $output_dir"
}

# Function to unpack crx file
unpack_crx() {
    crx_file=$1
    output_dir="${crx_file%.crx}"
    output_dir="${output_dir%-*}"
    rm -rf "$output_dir"
    mkdir -p "$output_dir"
    unzip -qq "$crx_file" -d "$output_dir"
    echo "Unpacked $crx_file to $output_dir"
}

# Function to remove extra bytes from a CRX file
clean_crx() {
    crx_file=$1
    clean_file="${crx_file%.crx}_clean.crx"

    # Find the start of the ZIP file by searching for the PK header
    start_byte=$(hexdump -C "$crx_file" | grep -m 1 'PK' | awk '{print "0x"$1}')
    if [ -z "$start_byte" ]; then
        echo "PK header not found in $crx_file"
        return 1
    fi

    # Extract the ZIP portion starting from the PK header
    tail -c +$((start_byte+1)) "$crx_file" > "$clean_file"

    echo "$clean_file"
}

# Function to get the current version of an installed extension
get_current_version() {
    crx_file=$1
    unzip -p "$crx_file" manifest.json | jq -r '.version'
}

# Iterate over all .crx files in the current directory
for crx in *.crx; do
    if [[ -f "$crx" ]]; then
        echo "Processing $crx..."

        # Get the current version of the installed extension
        current_version=$(get_current_version "$crx")
        echo "Current version: $current_version"

        # Clean up the CRX file by removing extra bytes
        clean_crx_file=$(clean_crx "$crx")
        if [ $? -ne 0 ]; then
            echo "Failed to clean $crx"
            continue
        fi

        echo "Cleaned CRX file: $clean_crx_file"
        echo "File size: $(stat -f %z "$clean_crx_file" 2>/dev/null || stat -c %s "$clean_crx_file" 2>/dev/null) bytes"

        # Extract the update URL from the cleaned .crx file
        update_url=$(unzip -p "$clean_crx_file" manifest.json | jq -r '.update_url')

        if [[ -z "$update_url" || "$update_url" == "null" ]]; then
            echo "No update URL found for $crx"
            rm "$clean_crx_file"
            continue
        fi

        echo "Update URL: $update_url"

        # Download the update XML, following redirections
        update_xml=$(curl -s -L "$update_url")

        if [[ -z "$update_xml" ]]; then
            echo "Failed to retrieve update XML from $update_url"
            rm "$clean_crx_file"
            continue
        fi

        echo "Update XML: $update_xml"

        # Extract the latest version and download URL from the update XML
        latest_version=$(echo "$update_xml" | xmllint --xpath 'string(//*[local-name()="updatecheck"]/@version)' - 2>/dev/null)
        download_url=$(echo "$update_xml" | xmllint --xpath 'string(//*[local-name()="updatecheck"]/@codebase)' - 2>/dev/null)

        echo "Latest version: $latest_version"
        echo "Download URL: $download_url"

        # Transform the download URL based on the source
        if [[ "$download_url" == *"github.com"* ]] || \
           [[ "$download_url" == *"gitflic.ru"* ]] || \
           [[ "$download_url" == *"gitlab.com"* ]]; then
            echo "Download URL from recognized source (GitHub, GitFlic.ru, or GitLab) detected, transforming to zip URL..."
            transformed_download_url=$(echo "$download_url" | sed 's/-[0-9]\+\.[0-9]\+\.[0-9]\+\.[0-9]\+\.crx$/-master.zip/')
            latest_file="${crx%.crx}-master.zip"
            echo "Transformed Download URL: $transformed_download_url"
        else
            transformed_download_url="$download_url"
            latest_file="${crx%.crx}.crx"
        fi

        # Check if the latest version is different from the current version or if the -f option is set
        unpacked_dir="${crx%.crx}"
        unpacked_dir="${unpacked_dir%-*}"
        if [[ "$latest_version" == "$current_version" && "$force_update" == false ]]; then
            if [[ "$latest_file" == *.zip && ! -d "$unpacked_dir" ]] || [[ "$latest_file" == *.crx && ! -d "$unpacked_dir" ]]; then
                echo "The latest version is not unpacked yet. Proceeding to unpack."
            else
                echo "The installed version is already the latest and unpacked. Skipping download."
                rm "$clean_crx_file"
                continue
            fi
        fi

        # Download the latest version of the file
        curl -s -L -o "$latest_file" "$transformed_download_url"

        if [[ ! -f "$latest_file" ]]; then
            echo "Failed to download the latest version of $crx"
            rm "$clean_crx_file"
            continue
        fi

        echo "Downloaded latest version of $crx: $latest_file"
        echo "File size: $(stat -f %z "$latest_file" 2>/dev/null || stat -c %s "$latest_file" 2>/dev/null) bytes"

        # Unpack the latest file (zip or crx)
        if [[ "$latest_file" == *.zip ]]; then
            unpack_zip "$latest_file"
        else
            unpack_crx "$latest_file"
        fi

        # Clean up
        rm "$clean_crx_file"
    fi
done

echo "All .crx files processed."
