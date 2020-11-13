#!/bin/sh

find diod
echo "moving all files in diod/low/trans to diod/high/trans"
mv diod/low/trans/* diod/high/trans > /dev/null 2>&1
