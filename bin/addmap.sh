#! /usr/bin/env bash
#
# addmap.sh
#
#      Copyright (c) 2020 Marc Munro
#      Author:  Marc Munro
#      License: GPL V3
#
# Usage:
#    addmap.sh htmldir maps...
#
# This is part of the process for creating maps for Marc's pretty
# ERDs.  This needs to be refactored into a stand-alon process.  Right
# now there is an unpleasantly coupled amagam of scripts and make
# targets.
#

# Add mapping to 1 source file
# Usage:
#  addmap imagename mapfile htmlfile
#
addmap () {
    mv $3 $3.unmapped
    
    gawk -v RS='>' '/<img.*\"'$1'/ {
    	 system("cat '$2'")
	 next
    }
    {
	printf("%s>", $0)
    }
    ' $3.unmapped >$3
}

htmldir=$1
shift

while [ "x$1" != "x" ]; do
    mapfile=$1
    imagename=`basename $1 | cut -d. -f1`
    find ${htmldir} -name '*html' -a -type f | \
	xargs grep -l "<img.*${imagename}" |
	while read filename; do
	    echo "Mapping ${filename}..."
	    addmap "${imagename}" "${mapfile}" "${filename}"
	done
    shift
done



