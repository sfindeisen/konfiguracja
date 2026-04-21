#!/usr/bin/env python3

"""
find_firefox_login.py
Searches all users' Firefox profiles under a given home base directory
for saved logins whose hostname contains a given substring (case-insensitive).

Usage: python3 find_firefox_login.py --hostname <search_string> [--home <path>]
"""

# Python 3.9 backward compatibility
from __future__ import annotations

import argparse
import json
import sys
from datetime import datetime, timezone
from pathlib import Path

# Width of the visual separator line printed between results.
# Chosen to comfortably fit "  Profile : <typical_profile_name>" (~40 chars).
SEPARATOR_WIDTH = 44


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Find Firefox saved logins by hostname substring."
    )
    parser.add_argument(
        "--hostname",
        required=True,
        metavar="SUBSTRING",
        help="Case-insensitive substring to search for in stored login hostnames.",
    )
    parser.add_argument(
        "--home",
        default="/home",
        metavar="PATH",
        help="Base directory containing user home folders (default: /home).",
    )
    return parser.parse_args()


def ms_to_local(ms: int | None) -> str:
    """Convert a Firefox millisecond-epoch timestamp to a local datetime string."""
    if not ms:
        return "n/a"
    return datetime.fromtimestamp(ms / 1000, tz=timezone.utc).astimezone().strftime("%Y-%m-%d %H:%M:%S %Z")


def firefox_profiles(home: Path) -> list[Path]:
    """Return all Firefox profile dirs containing a logins.json."""
    mozilla_dir = home / ".mozilla" / "firefox"
    if not mozilla_dir.is_dir():
        return []
    return [p.parent for p in mozilla_dir.glob("*/logins.json")]


def matching_entries(logins_file: Path, needle: str) -> list[dict]:
    """Return login entries from logins.json whose hostname contains needle (case-insensitive)."""
    try:
        data = json.loads(logins_file.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return []

    return [
        entry
        for entry in data.get("logins", [])
        if needle in (entry.get("hostname") or entry.get("origin", "")).lower()
    ]


def search(needle: str, home_base: Path) -> bool:
    """Search all user dirs under home_base. Returns True if any match was found."""
    if not home_base.is_dir():
        print(f"Error: home base directory '{home_base}' does not exist.", file=sys.stderr)
        sys.exit(1)

    needle_lower = needle.lower()
    separator = "-" * SEPARATOR_WIDTH
    found_any = False

    for user_dir in sorted(home_base.iterdir()):
        if not user_dir.is_dir():
            continue
        for profile_dir in firefox_profiles(user_dir):
            entries = matching_entries(profile_dir / "logins.json", needle_lower)
            if entries:
                found_any = True
                print(separator)
                print(f"  Path    : {profile_dir.resolve()}")
                for entry in entries:
                    hostname = entry.get("hostname") or entry.get("origin", "")
                    print(f"  ·  {hostname}")
                    print(f"       Last used        : {ms_to_local(entry.get('timeLastUsed'))}")
                    print(f"       Password changed : {ms_to_local(entry.get('timePasswordChanged'))}")
                    print(f"       Times used       : {entry.get('timesUsed', 'n/a')}")
                    print(f"       Created          : {ms_to_local(entry.get('timeCreated'))}")

    return found_any


def main() -> None:
    args = parse_args()

    if not search(args.hostname, Path(args.home)):
        print(f'No Firefox logins found containing "{args.hostname}".')


if __name__ == "__main__":
    main()

