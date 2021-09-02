#!/bin/sh

if [ $1 == 0 ]; then
    rpm --initdb --dbpath /tmp/rpmdb
    rpm --dbpath /tmp/rpmdb --nodeps -ihv --prefix /tmp/inst $2
else
    rm -rf /tmp/inst
    rm -rf /tmp/rpmdb
fi
