# My personal Unix-like system configuration

I hope you will find it useful. Just remember to replace my personal data (name, e-mail address) with yours.

## Local installation (unprivileged account) (automatic)

```
install.sh
```

This will configure the environment for the current user.

## Global system tweaks (root) (manual)

### X session forwarding with su(1)

Run `apt-get install libpam-modules` to install `pam_xauth.so`. It is likely to be already there. Then insert the following 2 lines into your `/etc/pam.d/su`:

```
# X session forwarding
session    optional   pam_xauth.so
```

## Cheatsheet

```
git config --list
```

## Credits

### vim

colors/solarized copied from https://github.com/altercation/vim-colors-solarized ; Copyright (c) 2011 Ethan Schoonover

