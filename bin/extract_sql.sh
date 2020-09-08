#!/usr/bin/env bash
#
#      extract_sql.sh
#
#      Copyright (c) 2020 Marc Munro
#      Author:  Marc Munro
#      License: GPL V3
#
# Usage:
#  extract_sql.sh [-d|-D] <docs_dir> <target_dir>
#
# This is very tightly bound to Marc's SQL coding style.  It does the
# job but is pretty fragile.
#
# Extract definitions from sql files to generate inclusions for
# docbook documentation.
#

# Usage:
#  extract_definition type name file
#
extract_definition ()
{
    gawk 'function start_reading() {
    	     reading = 1
	     if (started == 0) {
	         printf("<programlisting>\n")
		 started = 1
	     }
          }
	  BEGIN {
	      started = 0
	  }
	  /^create '$1'.*'$2'$/ { start_reading() }
	  /^create '$1'.*'$2' / { start_reading() }
          /^alter '$1'.*'$2' / { start_reading() }
          /^'$1'.*'$2'[\( ]/ { start_reading() }
          /^materialized '$1'.*'$2' / { start_reading() }
          /^materialized '$1'.*'$2'$/ { start_reading() }
	  (reading) { 
	      gsub(/&/, "\\&amp;")
	      gsub(/</, "\\&lt;")
	      gsub(/>/, "\\&gt;")
	      print
	  }
	  /;/ { 
	      if ("'$1'" == "function") {
	          # This is terrible code, irretrievably tied to
		  # Marc''s sql coding style.  Oh well.
	          if (($0 ~ /^language/) ||
		      ($0 ~ /^set /)) {
	              if (reading) printf("\n")
	      	      reading = 0
		  }
	      }
	      else {
	         if (reading) printf("\n")
	      	 reading = 0
	      }
	  }
	  END {
	      if (started) {
	         printf("</programlisting>\n")
	      }
	  }
' $3
}

# Usage:
#  extract_comments type name file
#
extract_comments ()
{
    gawk 'function start_reading() {
    	     reading = 1
	     in_quotes = 0
	     in_listing = 0
	     printf("<para>\n")
          }
	  function stop_reading() {
	     sub(/'"'"'[^'"'"']*$/, "") # Remove the closing quote
	     print_line()
	     if (in_listing) {
		 printf("</programlisting>\n")
		 in_listing = 0
	     }
	     printf("</para>\n")
	     reading = 0
          }
	  function print_line() {
	     gsub(/'"'"''"'"'/, "'"'"'") # Handle escaped quotes
	     print 
          }
	  # Lines indented by 4 spaces will be treated as
	  # programlisting entries.
	  function handle_listing() {
	     if ($0 == "") return
	     listing = match($0, /^    /)
	     if (listing) {
	         # Remove indentation
	         sub(/^    /, "")
	     }
	     if (in_listing) {
	         if (!listing) {
		     # That is the end of our programlisting section
		     printf("</programlisting>\n")
		     in_listing = 0
		 }
	     }
	     else {
	         if (listing) {
		     printf("<programlisting>\n")
		     in_listing = 1
		 }
	     }
          }
    	  /^comment on '$1'.*'$2'[\( ]/ {
	      start_reading()
	  }
    	  /^comment on materialized '$1'.*'$2' / {
	      start_reading()
	  }
          /^comment on column.*'$2'/ {
	      start_reading()
	      column_name = gensub(/.*on column [^\.]*.[^\.]*.(.*) is/,
	      		           "\\1", "g")
	      printf("Column <literal>%s</literal>: ", column_name)
	  }
	  (reading) {
	      quotes = length(gensub(/[^'"'"']*/, "", "g"))
	      if (in_quotes) {
	          # This is a continuing comment line.
		  if ($0 == "") {
		      if (!in_listing) {
		          printf("</para>\n<para>")
		      }
		  }
		  handle_listing()
		  if (quotes % 2) {
		      stop_reading()
		  }
		  else {
		      print_line()
		  }
	      }
	      else {
		  if (quotes) {
		     # This is the first line of a comment.  Remove
		     # everything before and including the first quote.
		     sub(/[^'"'"']*'"'"'/, "")
		     # If there is a closing quote, we remove that too.
		     if ((quotes % 2) == 0) {
		         stop_reading()
		     }
		     else {
		         print_line()
		     }
		  }
		  in_quotes = quotes % 2
	      }
	  }
' $3
}

#extract_definition trigger accessor_roles__aiudt sql/veil2/views.sql
#extract_comments trigger accessor_roles__aiudt sql/veil2/views.sql
#exit 1

if [ "x$1" = "x-D" ]; then
    # We have been asked to generate the dependencies for our
    # dependencies file.  This helps us figure out whether the
    # dependencies list is out of date.
    shift
    find $1 -name '*xml' | xargs grep -l '<?sql-definition' |
	sort -u | xargs
elif [ "x$1" = "x-d" ]; then
    # We have been asked to generate the dependencies between our
    # extracted sql definitions and their source files.
    shift
    version=`cut -d" " -f1 VERSION`
    find $1 -name '*xml' | xargs \
        gawk '/<?sql-definition/ {printf("'$2'/%s.xml: %s\n", $3, $4)}' |
	sed -e "s/&version_number;/${version}/" | sort -u
else
    version=`cut -d" " -f1 VERSION`
    find $1 -name '*xml' | xargs \
        gawk '/<?sql-definition/ {print $2, $3, $4}' | 
	sed -e "s/&version_number;/${version}/" | sort -u |
        while read objtype name file; do
    	echo Creating extract for ${name}...
    	(
    	    echo "<extract>"
                extract_definition ${objtype} ${name} ${file}
    	    extract_comments ${objtype} ${name} ${file}
    	    echo "</extract>"
    	) >$2/${name}.xml
        done
fi
