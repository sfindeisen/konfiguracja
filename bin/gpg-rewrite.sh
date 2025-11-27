#!/bin/bash
#
# Re-encrypts the given PGP message file using the default key.

set -o errexit
set -o noglob
set -o notify
set -o pipefail

ARGC=$#

if test $ARGC -lt 1 || test $ARGC -gt 2 || test "--help" = "$1" || test $ARGC -eq 2 && test "--no-verify" != "$1" ; then
  echo "usage: $0 [--no-verify] FILE";
  exit 1;
fi

if [ $# -eq 2 ] ; then
NOVER=1
FILE="$2"
else
NOVER=0
FILE="$1"
fi

if [ ! -f "$FILE" ] ; then
  echo "usage: $0 [--no-verify] FILE";
  exit 2;
fi

# verify PGP signature
if [ 1 -ne $NOVER ] ; then
  FIRST_LINE=$(head -n1 "$FILE")
  case "$FIRST_LINE" in
    "-----BEGIN PGP SIGNED MESSAGE-----")
    gpg --verify "$FILE"
    ;;
    "-----BEGIN PGP SIGNATURE-----")
    echo "Detached signature - you need the original file too. Exiting"
    exit 3;
    ;;
    "-----BEGIN PGP MESSAGE-----")
    gpg --decrypt --output /dev/null "$FILE"
    ;;
    *)
    echo "Unknown PGP format."
    exit 4;
    ;;
  esac
fi

# re-encrypt
umask 0077
TMPFILE=`mktemp`
echo "using tempfile: $TMPFILE"
cat "$FILE" | gpg --decrypt | gpg --armor --sign --encrypt > "$TMPFILE"
mv "$TMPFILE" "$FILE"
