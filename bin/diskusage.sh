#!/bin/bash
#
# Prints disk usage of the current dir and each of its entries.

du -ha -d 1 | sort -h

