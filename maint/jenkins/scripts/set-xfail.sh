#!/bin/bash
#
# Copyright (C) by Argonne National Laboratory.
#     See COPYRIGHT in top-level directory.
#

jobname=""
compiler=""
configs=""
direct=""
provider=""
am=""
pmix="nopmix"

XFAIL_CONF="xfail.conf"

#####################################################################
## Initialization
#####################################################################

while getopts ":f:j:c:o:s:m:a:p:" opt; do
    case "$opt" in
        j)
            jobname=$OPTARG ;;
        c)
            compiler=$OPTARG ;;
        o)
            configs=$OPTARG ;;
        s)
            direct=$OPTARG ;;
        m)
            provider=$OPTARG ;;
        a)
            am=$OPTARG ;;
        p)
            pmix=$OPTARG ;;
        f)
            XFAIL_CONF=$OPTARG ;;
        \?)
            echo "Invalid option: -$OPTARG" >&2
            exit 1
    esac
done

#####################################################################
## Main (
#####################################################################

if test ! -f "$XFAIL_CONF" ; then
    echo "Cannot find $XFAIL_CONF. No XFAIL will be applied"
    exit 0
fi

XFAILCond() {
    local job="$1"
    local comp="$2"
    local option="$3"
    local nmod="$4"
    local directconfig="$5"
    local amconfig="$6"
    local pmixconfig="$7"

    local state=0

    if [[ ! "$job" == "*" ]]; then
        # clean up jobname and do substring match
        if [[ ! "${jobname%%,*}" == *$job* ]]; then state=1; fi
    fi

    if [[ ! "$comp" == "*" ]]; then
        if [[ ! "$compiler" == "$comp" ]]; then state=1; fi
    fi

    if [[ ! "$option" == "*" ]]; then
        if [[ ! "$configs" == "$option" ]]; then state=1; fi
    fi

    if [[ ! "$nmod" == "*" ]]; then
        if [[ ! "$provider" == "$nmod" ]]; then state=1; fi
    fi

    if [[ ! "$directconfig" == "*" ]]; then
        if [[ ! "$direct" == "$directconfig" ]]; then state=1; fi
    fi

    if [[ ! "$amconfig" == "*" ]]; then
        if [[ ! "$am" == "$amconfig" ]]; then state=1; fi
    fi

    if [[ ! "$pmixconfig" == "*" ]]; then
        if [[ ! "$pmix" == "$pmixconfig" ]]; then state=1; fi
    fi

    echo "$state"
}

SCRIPT="apply-xfail.sh"
if [[ -f $SCRIPT ]]; then
    rm $SCRIPT
fi

while read -r line; do
    #clean leading whitespaces
    line=$(echo "$line" | sed "s/^ *//g")
    line=$(echo "$line" | sed "s/ *$//g")
    echo "$line"
    # skip comment line
    if test -x "$line" -o "${line:0:1}" = "#" ; then
        continue
    fi

    IFS=' ' read -r -a arr <<< $line

    xfail_state=$(XFAILCond "${arr[0]}" "${arr[1]}" "${arr[2]}" "${arr[3]}" "${arr[4]}" "${arr[5]}" "${arr[6]}")

    if [[ "$xfail_state" == "0" ]]; then
        echo "${arr[@]:7}" >> $SCRIPT
    fi
done < "$XFAIL_CONF"

if [[ -f $SCRIPT ]]; then
    source $SCRIPT
fi

exit 0
