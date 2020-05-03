# GNUmakefile
#
#      Main Makefile for veil2
#
#      Copyright (c) 2020 Marc Munro
#      Author:  Marc Munro
#      License: GPL V3
#
# For a list of targets use make help.
# 

.PHONY: db drop clean help unit check test html htmldir

include Makefile.global

all: db

SUBDIRS = demo docs docs/parts sql sql/veil2 

###
# Docs
# This section of the Makefile is all about building documentation.
#

DOC_SOURCES := $(wildcard docs/*.xml) $(wildcard docs/parts/*.xml) 
BASE_STYLESHEET := $(DOCBOOK_STYLESHEETS)/html/chunkfast.xsl
VEIL2_STYLESHEET := docs/html_stylesheet.xsl

# This is the phony target for the html documentation.  This target
# builds the html documentation.
#
html: html/index.html

# Build the version entity for the docbook documentation.  This is
# included into the docbook source.
#
docs/version.sgml: VERSION configure
	{ \
	  echo "<!ENTITY version \"$(VERSION)\">"; \
	  echo "<!ENTITY majorversion \"$(MAJOR_VERSION)\">"; \
	} > $@


# Do the legwork of building our html documentation from docbook
# sources. 
html/index.html: $(DOC_SOURCES) docs/version.sgml
	@[ -d html ] || mkdir html # Create the directory, if needed.
	@echo XSLTPROC "<docbook sources>.xml -->" $@
	$(XSLTPROC) $(XSLTPROCFLAGS) --output html/ \
		$(VEIL2_STYLESHEET) docs/veil2.xml

###
# Clean
# This section is about cleaning up the directory space.
#

# What constitutes general garbage files.
garbage_files := \\\#*  .\\\#*  *~ 

# Directories that are built by this Makfile and may be removed.
built_dirs := html

clean:
	@echo $(SUBDIRS)
	@for i in $(SUBDIRS); do \
	   echo Cleaining $${i}...; \
	   (cd $${i}; rm -f $(garbage_files)); \
	done

distclean: clean
	rm -rf Makefile.global ./configure autom4te.cache config.log
	@for i in $(built_dirs); do \
	   echo Cleaining $${i}...; \
	   rm -rf $${i}; \
	done

###
# Main
# This section is about installing testing and cleaning-up veil2
# database objects.
#

TESTDB := vpd

db:
	@if (psql -l | grep $(TESTDB) >/dev/null 2>&1); then \
	    echo "[database already exists]"; \
        else \
	    echo "Creating database..."; \
	    psql -v dbname="$(TESTDB)" -f sql/create_vpd.sql; \
	fi

drop:
	@psql -c "drop database $(TESTDB)"
	@psql -c "drop role veil_user"

# You can run this using several target names.  It requires the VPD
# database to exist and will create it if necessary.
# The grep below is used to eliminate lines that begin with '##'.  In
# order to make the output cleaner, the unit test script prepends ##
# to the output of any queries that it makes internally for setting
# variables.
unit check test: db
	@echo "Performing unit tests..."
	@psql -v flags=$(FLAGS) -f test/test_veil2.sql -d $(TESTDB) | grep -v '^##'


# Provide a list of the targets buildable by this makefile.
list help:
	@echo "\n\
 Major targets for this makefile are:\n\n\
 help         - show this list of major targets\n\
 db           - build standalone '$(TESTDB)' database\n\
 drop         - drop standalone '$(TESTDB)' database\n\
 unit         - run unit tests (uses '$(TESTDB)' database, takes FLAGS variable)\n\
   test       - ditto (a synonym for unit)\n\
   check      - ditto (a synonym for unit)\n\
 html         - create html documentation\n\
 clean        - clean out unwanted files\n\
\n\
"
