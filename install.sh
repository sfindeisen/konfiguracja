#!/bin/bash

umask 0077

SCRIPT_DIR=`dirname "$(readlink -f "$0")"`

function dircopy() {
  FROM_DIR=$1
  TO_DIR=$2

  if [ -d "${TO_DIR}" ] ; then
    cp -vr ${FROM_DIR}/* "${TO_DIR}/"
  else
    cp -vr ${FROM_DIR}   "${TO_DIR}"
  fi
}

function install_dir() {
  INST_DIR=$1
  dircopy "${SCRIPT_DIR}/${INST_DIR}" "${HOME}/${INST_DIR}"
}

function install_file() {
  INST_FILE=$1
  cp -v "${SCRIPT_DIR}/${INST_FILE}" "${HOME}/"
}

install_dir  bin
install_dir .config
install_dir .gnupg
install_dir .stack
install_dir .vim

install_file .emacs
install_file .gitconfig

cat "$SCRIPT_DIR/.profile" >> "${HOME}/.profile"
cat "$SCRIPT_DIR/.bash_aliases" >> "${HOME}/.bash_aliases"
