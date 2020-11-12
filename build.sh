#!/bin/sh

#ASC="`date '+%Y%m%d%H%M%S'`.asc"
ASC="19700101235959.asc"
FILES="build.sh LICENSE README.md"

if [ ! -d diod/high ]; then
	mkdir -p diod/high
fi
if [ ! -d diod/src ]; then
	mkdir -p diod/src
fi
if [ ! -d diod/trans ]; then
	mkdir -p diod/trans
fi
if [ ! -d diod/dst ]; then
	mkdir -p diod/dst
fi

rm diod/dst/*
rm diod/src/*
rm diod/trans/*

cp $FILES diod/src
truncate --size=1M diod/src/bigfile
rm -f diod/src/$ASC
(cd diod/src; sha256sum *  > /tmp/$ASC)

cp /tmp/$ASC diod/src
