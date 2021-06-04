#!/bin/sh

#ASC="`date '+%Y%m%d%H%M%S'`.asc"
ASC1="19700101235959.asc"
ASC2="19720101235959.asc"
FILES1="build.sh LICENSE README.md"
FILES2="transfer.pl Transfer.pm diod.sh conf.high conf.low"

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

# file1
TMP1=/tmp/tmp.1
if [ ! -d $TMP1 ]; then
    mkdir $TMP1
fi
cp $FILES1 $TMP1
truncate --size=1M $TMP1/bigfile1
rm -f $TMP1/$ASC1
(cd $TMP1; sha256sum *  > /tmp/$ASC1)
cp /tmp/$ASC1 $TMP1
mv $TMP1/* diod/low/src

TMP2=/tmp/tmp.2
if [ ! -d $TMP2 ]; then
    mkdir $TMP2
fi
cp $FILES2 $TMP2
truncate --size=1M $TMP2/bigfile2
rm -f $TMP2/$ASC2
(cd $TMP2; sha256sum *  > /tmp/$ASC2)
cp /tmp/$ASC2 $TMP2
mv $TMP2/* diod/low/src


#cp $FILES diod/low/src
#truncate --size=1M diod/low/src/bigfile
#rm -f diod/low/src/$ASC
#(cd diod/low/src; sha256sum *  > /tmp/$ASC)
#
#cp /tmp/$ASC diod/low/src
