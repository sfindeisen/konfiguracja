#!/bin/bash
#
# Combined install and upgrade script

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
install_file .gitignore

################################################################
# custom .bashrc
################################################################

if [ -f ~/.bashrc_sf ]; then
echo "File ~/.bashrc_sf already exists, refuse to modify ~/.bashrc"
else
echo "modify ~/.bashrc"
cat <<'EOF' >> $HOME/.bashrc

if [ -f ~/.bashrc_sf ]; then
    . ~/.bashrc_sf
fi
EOF
fi

install_file .bash_aliases_sf
install_file .bashrc_sf

################################################################
# custom .profile
################################################################

if [ -f ~/.profile_sf ]; then
echo "File ~/.profile_sf already exists, refuse to modify ~/.profile"
else
echo "modify ~/.profile"
cat <<'EOF' >> $HOME/.profile

if [ -f "$HOME/.profile_sf" ]; then
    . "$HOME/.profile_sf"
fi
EOF
fi

install_file .profile_sf
