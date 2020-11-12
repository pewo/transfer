#!/bin/sh

#ASC="`date '+%Y%m%d%H%M%S'`.asc"
ASC="19700101235959.asc"
FILES="build.sh LICENSE README.md"

if [ ! -d diod/high/trans ]; then
	mkdir -p diod/high/trans
fi
if [ ! -d diod/high/dst ]; then
	mkdir -p diod/high/dst
fi
if [ ! -d diod/low/src ]; then
	mkdir -p diod/low/src
fi
if [ ! -d diod/low/trans ]; then
	mkdir -p diod/low/trans
fi

rm diod/low/*/*
rm diod/high/*/*

cp $FILES diod/low/src
truncate --size=1M diod/low/src/bigfile
rm -f diod/low/src/$ASC
(cd diod/low/src; sha256sum *  > /tmp/$ASC)

cp /tmp/$ASC diod/low/src
