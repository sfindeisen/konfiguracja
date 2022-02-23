# Stanislaw's personal Unix-like system configuration

## Local installation (unprivileged account) (automatic)

```
install.sh
```

This will modify your `$HOME`.

## Global system tweaks (root) (manual)

### X session forwarding with su(1)

Run `apt-get install libpam-modules` to install `pam_xauth.so`. It is likely to be already there. Then insert the following 2 lines into your `/etc/pam.d/su`:

```
# X session forwarding
session    optional   pam_xauth.so
```

## Credits

### vim

colors/solarized copied from https://github.com/altercation/vim-colors-solarized ; Copyright (c) 2011 Ethan Schoonover

