#! /usr/bin/env bash
#
# Usage: get_doxygen_anchors.sh tagfile sourcedir targetdir
#
# Extract anchor information for links to doxygen documentation from
# our docbook sources.  We extract only those that we need, which we
# determine by scanning the docbook sources for <?doxygen-ulink>
# processing instructions.
#

get_tag ()
{
    awk '
        /<\/member>/ {
	    looking = 0
	}
        /<name>'$3'<\/name>/ {
	    # If we are currently looking then we will still be.
	    next
	}
        /<name>/ {
	    # Wrong name.  Stop looking.
	    looking = 0
	}
	/<anchorfile>/ {
	    if (looking) {
	        sub(/ *<anchorfile>/, "")
	        sub(/<\/anchorfile>/, "")
		file=$0
	    }
	}
	/<anchor>/ {
	    if (looking) {
	        sub(/ *<anchor>/, "")
	        sub(/<\/anchor>/, "")
		anchor=$0
		printf("<anchor>%s#%s</anchor>\n", file, anchor)
		exit
	    }
	}
        /<member kind=\"'$2'\"/ {
	    looking = 1
	}' $1 TYPE=$2 NAME=$3
}

find $2 -name '*xml' | xargs cat - | \
    grep '<?doxygen-ulink' | sed -e 's/?>.*//' |
    while read dummy type name dummy2; do
	echo "...${type}_${name}.anchor"
	get_tag $1 $type $name >$3/${type}_${name}.anchor
    done
