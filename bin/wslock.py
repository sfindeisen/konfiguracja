#!/usr/bin/env python3

"""
wslock.py
Keeps you off one workspace during set time windows: whenever that
workspace becomes active during a blocked window, switches back to the
previous workspace a moment later. Runs until the X session ends.

Debian packages: python3-gi gir1.2-wnck-3.0
"""

import datetime

import gi

gi.require_version("Gtk", "3.0")
gi.require_version("Wnck", "3.0")
from gi.repository import GLib, Gtk, Wnck

# The workspace to lock: its name (a string) or its number (an int, from 1).
WORKSPACE = "offspace"

# When it is locked: (weekdays, start, end), with Monday being 0. The end
# is exclusive; a window must not cross midnight, so split it in two.
BLOCKED = [
    (range(0, 6), "08:00", "19:00"),  # Mon-Sat
    ((6,), "11:00", "18:30"),         # Sun
]

# How long to stay on the locked workspace before switching back, in
# milliseconds. Switching back at once is so fast that the panel's
# Workspace Switcher can miss both changes and keep the locked workspace's
# button highlighted next to the active one.
SWITCH_BACK_DELAY_MS = 100


def is_blocked():
    now = datetime.datetime.now()
    hhmm = now.strftime("%H:%M")
    return any(now.weekday() in days and start <= hhmm < end
               for days, start, end in BLOCKED)


def is_locked(workspace):
    return (workspace is not None
            and WORKSPACE in (workspace.get_name(), workspace.get_number() + 1)
            and is_blocked())


def switch_back(screen, previous):
    # The locked workspace may have been left, or unlocked, in the meantime.
    if is_locked(screen.get_active_workspace()):
        # Timestamp 0 makes the window manager use the current time.
        previous.activate(0)
    return GLib.SOURCE_REMOVE


def on_active_workspace_changed(screen, previous):
    # Without a previous workspace this is wnck's initial update, not a
    # switch: being on the locked workspace already is fine.
    if previous is not None and is_locked(screen.get_active_workspace()):
        GLib.timeout_add(SWITCH_BACK_DELAY_MS, switch_back, screen, previous)


Wnck.Screen.get_default().connect("active-workspace-changed",
                                  on_active_workspace_changed)
Gtk.main()
