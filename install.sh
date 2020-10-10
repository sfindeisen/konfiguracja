#!/bin/bash

SCRIPT_DIR=`dirname "$(readlink -f "$0")"`

cp -rv "${SCRIPT_DIR}/.emacs" "$HOME"
cp -rv "${SCRIPT_DIR}/.stack" "$HOME"
cp -rv "${SCRIPT_DIR}/.vim"   "$HOME"

cat "$SCRIPT_DIR/.profile" >> "${HOME}/.profile"

"${SCRIPT_DIR}/git/init.sh"

