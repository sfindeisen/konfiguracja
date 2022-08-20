#!/bin/bash
#
# Decrypts the given file.

set -o errexit
set -o noglob
set -o notify
set -o pipefail

ARGC=$#

if test $ARGC -ne 1 || test "--help" = "$1" ; then
  echo "usage: $0 FILE";
  exit 1;
fi

FILE="$1"

if [ ! -f "$FILE" ] ; then
  echo "usage: $0 FILE";
  exit 2;
fi

umask 0077
gpg -d "$FILE"
