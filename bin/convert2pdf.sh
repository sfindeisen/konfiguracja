#!/bin/bash

for FILE in "$@" ; do
  convert "$FILE" -units pixelsperinch -density 72 -page A4 "${FILE}.pdf" ;
done

