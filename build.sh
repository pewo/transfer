#!/bin/sh

#ASC="`date '+%Y%m%d%H%M%S'`.asc"
ASC="19700101235959.asc"
FILES="build.sh LICENSE README.md"

sha256sum $FILES  > /tmp/$ASC
cp $FILES diod/src
cp /tmp/$ASC diod/src
