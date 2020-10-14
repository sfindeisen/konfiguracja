#!/bin/bash

SCRIPT_DIR=`dirname "$(readlink -f "$0")"`

cp -v  "${SCRIPT_DIR}/.emacs"      "$HOME"
cp -v  "${SCRIPT_DIR}/.gitconfig"  "$HOME"
cp -vr "${SCRIPT_DIR}/.stack"      "$HOME"
cp -vr "${SCRIPT_DIR}/.vim"        "$HOME"

cat "$SCRIPT_DIR/.profile" >> "${HOME}/.profile"
cat "$SCRIPT_DIR/.bash_aliases" >> "${HOME}/.bash_aliases"
