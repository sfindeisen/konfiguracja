#!/usr/bin/env bash

# -----------------------------------------------------------------------------
# Atomic in-place text normalization for a file.
#
# Replacements:
#   ’  -> '
#   —  -> ---
#   –  -> --
#
# Approach:
#   - Writes transformed content to a temp file in same directory
#   - Atomically replaces original file using mv
#   - Guarantees no partial writes (atomic rename on same filesystem)
#
# Note:
#   - Atomicity holds only if temp file and target are on same filesystem
#   - No backup file is created; original is replaced immediately
# -----------------------------------------------------------------------------

set -euo pipefail

file="$1"

# -----------------------------------------------------------------------------
# Validate input
# -----------------------------------------------------------------------------
if [[ -z "${file:-}" || ! -f "$file" ]]; then
  echo "Usage: $0 <file>"
  exit 1
fi

# -----------------------------------------------------------------------------
# Create temp file in same directory (required for atomic rename)
# -----------------------------------------------------------------------------
dir="$(dirname "$file")"
base="$(basename "$file")"

tmp="$(mktemp "$dir/.${base}.tmp.XXXXXX")"

# -----------------------------------------------------------------------------
# Apply text transformations
#   - Curly apostrophe → straight apostrophe
#   - Em dash → triple hyphen
#   - En dash → double hyphen (TeX-style)
# -----------------------------------------------------------------------------
sed "s/’/'/g; s/—/---/g; s/–/--/g; s/“/\"/g; s/”/\"/g;" "$file" > "$tmp"

# -----------------------------------------------------------------------------
# Atomically replace original file
# -----------------------------------------------------------------------------
mv "$tmp" "$file"

