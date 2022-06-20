#!/bin/bash
#
# Prints disk usage of the current dir and each of its entries.

du -ch -d 1 . | sort -hr

