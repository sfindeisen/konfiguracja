#!/usr/bin/env python3

"""
wslock.py
Keeps you off one workspace during set time windows: whenever that
workspace becomes active during a blocked window, switches straight back
to the previous workspace. Runs until the X session ends.

Debian packages: python3-gi gir1.2-wnck-3.0
"""

import datetime

import gi

gi.require_version("Gtk", "3.0")
gi.require_version("Wnck", "3.0")
from gi.repository import Gtk, Wnck

# The workspace to lock: its name (a string) or its number (an int, from 1).
WORKSPACE = "Distractions"

# When it is locked: (weekdays, start, end), with Monday being 0. The end
# is exclusive; a window must not cross midnight, so split it in two.
BLOCKED = [
    (range(0, 5), "08:00", "12:00"),
    (range(0, 5), "13:00", "17:30"),
]


def is_blocked():
    now = datetime.datetime.now()
    hhmm = now.strftime("%H:%M")
    return any(now.weekday() in days and start <= hhmm < end
               for days, start, end in BLOCKED)


def on_active_workspace_changed(screen, previous):
    active = screen.get_active_workspace()
    # Without a previous workspace this is wnck's initial update, not a
    # switch: being on the locked workspace already is fine.
    if (previous is not None and active is not None
            and WORKSPACE in (active.get_name(), active.get_number() + 1)
            and is_blocked()):
        # Timestamp 0 makes the window manager use the current time.
        previous.activate(0)


Wnck.Screen.get_default().connect("active-workspace-changed",
                                  on_active_workspace_changed)
Gtk.main()
