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

if [ 1 -ne $NOVER ] ; then
  gpg --verify "$FILE"
fi

TMPFILE=`mktemp`
echo "using tempfile: $TMPFILE"
cat "$FILE" | gpg -d | gpg -a -s -e > "$TMPFILE"
mv "$TMPFILE" "$FILE"
