#!/bin/bash
#
# A script for stripping off binary files from a code repo.

# Directory to clean; must be explicitly specified.
dir="${1:-}"

# Basic safety checks.
if [ -z "$dir" ] || [ ! -d "$dir" ]; then
    echo "Usage: $0 DIRECTORY" >&2
    exit 1
fi

# Delete backup files and JPEG/PNG images.
# -P: never follow symbolic links.
find -P "$dir" -type f \
    \( -name '*~' -o -name '*.jpeg' -o -name '*.jpg' -o -name '*.png' \) \
    -exec rm -f -- {} +

# Delete Python cache directories.
find -P "$dir" -type d -name '__pycache__' \
    -exec rm -rf -- {} +
