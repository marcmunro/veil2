# GNUmakefile
#
#      Makefile for veil2
#
#      Copyright (c) 2020 Marc Munro
#      Author:  Marc Munro
#      License: GPL V3
#
# For a list of targets use make help.
#
# Most of this makefile is concerned with building the html
# documentation.  The basic process is simple, but is complicated by
# Marc's wish to automatically create html maps from dia ERD diagrams
# so that the diagrams can be used to navigate to entity descriptions.
# Oh, and also to create automated documentation from the sql
# scripts.  The GNUmakefiles in subdirectories are just there to 
# automatically invoke this makefile ins such a way that emacs'
# compile and next-error handling still works if you are not in the
# root directory.
# 

.PHONY: db drop clean help unit check test html \
	htmldir images maps unmapped extracts

include Makefile.global
include extracts.d

all: db html

SUBDIRS = demo docs docs/extracts docs/parts sql sql/veil2 diagrams test

INTERMEDIATE_FILES =
TARGET_FILES =
TARGET_DIRS =

###
# Extracts
# These are extracts from sql files used to help build the
# documentation.  The dependencies here are many, somewhat complex and
# prone to changing, so we automate their generation.
#
extracts.d:
	@echo Recreating extracts dependency file $@...
	@echo "$@: `bin/extract_sql.sh -D docs docs/extracts`" >$@
	@bin/extract_sql.sh -d docs docs/extracts >>$@
	@echo "EXTRACTS := \
	    `bin/extract_sql.sh -d docs docs/extracts | \
	     cut -d: -f1 | xargs`" >>$@

INTERMEDIATE_FILES += extracts.d

# Phony target
extracts: $(EXTRACTS)


$(EXTRACTS): 
	@echo Recreating sql extracts for docs...
	@[ -d docs/extracts ] || mkdir docs/extracts 
	@bin/extract_sql.sh docs docs/extracts

TARGET_FILES += $(EXTRACTS)
TARGET_DIRS += docs/extracts

###
# Docs
# This section of the Makefile is all about building documentation.
#

DOC_SOURCES := $(wildcard docs/*.xml) $(wildcard docs/parts/*.xml) 
BASE_STYLESHEET = $(DOCBOOK_STYLESHEETS)/html/chunkfast.xsl
VEIL2_STYLESHEET = docs/html_stylesheet.xsl
STYLESHEET_IMPORTER = docs/system-stylesheet.xsl
VERSION_FILE = docs/version.sgml

INTERMEDIATE_FILES += $(STYLESHEET_IMPORTER) $(VERSION_FILE)
HTMLDIR = html
TARGET_FILES += $(HTMLDIR)/* 
TARGET_DIRS += $(HTMLDIR)

DIAGRAMS_DIR := diagrams
DIAGRAM_SOURCES := $(wildcard $(DIAGRAMS_DIR)/*.dia)
DIAGRAM_IMAGES := $(DIAGRAM_SOURCES:%.dia=%.png)
DIAGRAM_XMLS := $(DIAGRAM_SOURCES:%.dia=%.xml)
DIAGRAM_COORDS := $(DIAGRAM_SOURCES:%.dia=%.coords)
DIAGRAM_MAPS := $(DIAGRAM_SOURCES:%.dia=%.map)
DIAGRAM_INTERMEDIATES := $(DIAGRAM_IMAGES) $(DIAGRAM_XMLS) \
			 $(DIAGRAM_COORDS) $(DIAGRAM_MAPS)
INTERMEDIATE_FILES += $(DIAGRAM_INTERMEDIATES)

TARGET_IMAGES := $(patsubst $(DIAGRAMS_DIR)%, $(HTMLDIR)%, $(DIAGRAM_IMAGES))

# Copy new images to html dir
#
$(HTMLDIR)/%: $(DIAGRAMS_DIR)/% 
	@[ -d html ] || mkdir html # Create the directory, if needed.
	cp $< $@

# For building diagram images
#
%.png: %.dia
	@echo "Rebuilding $@ from $<..."
	dia --nosplash  --export=$*.eps $< 2>/dev/null
	pstoimg -antialias -transparent -crop tblr -scale 0.5 $*.eps
	@rm $*.eps

# Intermediate file used for creating maps from our diagrams.
#
%.xml: %.dia
	@echo Creating XML Version of dia file $<...
	@cp -f $< $*.xml.gz
	@{ [ -f $*.xml ] && rm $*.xml; } || true
	@gunzip $*.xml.gz

# Coordinates file - an intermediate for mapping diagrams
#
%.coords: %.xml
	@echo Creating XML Coordinates file $<...
	@xsltproc bin/dia_to_map.xsl $*.xml | xmllint --format \
	 --recover - >$*.coords

# map file - an intermediate for mapping diagrams
#
%.map: %.coords %.png $(HTMLDIR)/index.html
	@echo Creating HTML map file $<...
	bin/erd2map $* $(HTMLDIR) >$*.map

# Phony target for building image files.
#
images: $(DIAGRAM_IMAGES)

# Phony target for building html map files for images
#
maps: $(DIAGRAM_MAPS) $(DIAGRAM_COORDS) $(DIAGRAM_IMAGES)


# Create stylesheet to import base stylesheet from system.  This
# allows the base stylesheet which was discovered by configure to be
# automatically imported into our local stylesheet.
#
$(STYLESHEET_IMPORTER): Makefile.global
	@echo "Creating importer for system base stylesheet for docs..."
	@{ \
	  echo "<?xml version='1.0'?>"; \
	  echo "<xsl:stylesheet"; \
	  echo "   xmlns:xsl=\"http://www.w3.org/1999/XSL/Transform\""; \
	  echo "   version=\"1.0\">"; \
	  echo "  <xsl:import"; \
	  echo "     href=\"$(BASE_STYLESHEET)\"/>"; \
	  echo "</xsl:stylesheet>"; \
	} > $@

# These are the phony target for the html documentation.  The index.html
# dependency is the real target html target.  The mapped target is
# used to add image maps to the pre-created html.  If the image
# mapping stuff fails, you can build a less functional version of the
# html using the unmapped target.
#
unmapped: $(HTMLDIR)/index.html

html: $(HTMLDIR)/mapped


# Build the version entity for the docbook documentation.  This is
# included into the docbook source.
#
$(VERSION_FILE): VERSION configure
	@echo "Creating version entities for docs..."
	@{ \
	  echo "<!ENTITY version \"$(VERSION)\">"; \
	  echo "<!ENTITY majorversion \"$(MAJOR_VERSION)\">"; \
	} > $@


# Do the legwork of building our html documentation from docbook
# sources.   The index.html file is built by this, but so are loads of
# other html files.  We are using index.html as a proxy to mean *all*
# html files.
#
$(HTMLDIR)/index.html: $(DOC_SOURCES) $(VERSION_FILE) $(VEIL2_STYLESHEET) \
		 $(STYLESHEET_IMPORTER) $(TARGET_IMAGES) $(EXTRACTS)
	@[ -d html ] || mkdir html # Create the directory, if needed.
	@echo XSLTPROC "<docbook sources>.xml -->" $@
	$(XSLTPROC) $(XSLTPROCFLAGS) --output html/ \
		$(VEIL2_STYLESHEET) docs/veil2.xml

# The "mapped" file is an indicator that image maps, for ERDs,  have
# been created and applied to our html targets.
#
$(HTMLDIR)/mapped: $(HTMLDIR)/index.html $(DIAGRAM_MAPS)
	@bin/addmap.sh $(HTMLDIR) $(DIAGRAM_MAPS)
	@touch $@


###
# Clean
# This section is about cleaning up the directory space.
#

# What constitutes general garbage files.
garbage_files := \\\#*  .\\\#*  *~ 

clean:
	@echo $(SUBDIRS)
	@for i in $(SUBDIRS); do \
	   echo Cleaning $${i}...; \
	   (cd $${i}; rm -f $(garbage_files)) 2>/dev/null; \
	done || true
	echo Cleaning intermediate and target files...
	@rm -f $(INTERMEDIATE_FILES) $(TARGET_FILES) 2>/dev/null || true
	@rmdir $(TARGET_DIRS) 2>/dev/null || true

distclean: clean
	rm -rf Makefile.global ./configure autom4te.cache config.log

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
 images       - create all diagram images from sources\n\
 extracts     - create all doc extracts sql scripts\n\
 maps         - create all html maps for diagram images\n\
 clean        - clean out unwanted files\n\
\n\
"
