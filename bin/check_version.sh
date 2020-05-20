#! /usr/bin/env bash
#
#      check_version.sh
#
#      Copyright (c) 2020 Marc Munro
#      Author:  Marc Munro
#      License: GPL V3
#
# Get Veil2's version from our local repo, a remote repo, or
# Makefile.global.  Print or compare the versions.
#
# Usage:




VERSION_FILE=VERSION

local_ver ()
{
    cat `dirname $0`/../VERSION
}

makefile_ver ()
{
    grep "^VERSION=" `dirname $0`/../Makefile.global | cut -f2-
}

# Fetch VERSION curl, return a failure if not found
repo_ver ()
{
    content=`curl $1 2>/dev/null` || return 3
    (echo "${content}" | grep "404:" >/dev/null) && return 4
    echo "${content}"
}



ver=""
ver1=""
ver2=""

while [ "x$1" != "x" ]; do
    if [ "x$1" = "x-l" ]; then
	ver=`local_ver`
    elif [ "x$1" = "x-m" ]; then
	ver=`makefile_ver`
    elif [ "x$1" = "x-r" ]; then
	if [ "x$2" = "x" ]; then
	    echo "`basename $0`: Missing arg.  -r option requires repo." 1>&2
	    exit 2
	fi
	ver=`repo_ver "$2"` ||
	    { echo "`basename $0`: Unable to fetch version file from repo." 1>&2
	      exit 3; }
	shift 
    else
	echo "`basename $0`: Unexpected arg: $1" 1>&2
	exit 2
    fi
    
    if [ "x${ver1}" = "x" ]; then
        ver1="${ver}"
    elif [ "x${ver2}" != "x" ]; then
	echo "`basename $0`: too many options."
    else
        ver2="${ver}"
    fi
    shift
done

if [ "x${ver2}" = "x" ]; then
    echo ${ver1}
else
    [ "x${ver1}" = "x${ver2}" ]
fi
