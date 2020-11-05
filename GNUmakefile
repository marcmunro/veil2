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
# At some point we should add some targets for dealing with releases
# to github.
# For now, know this.
# the branch gh-pages is for documentation.  Merge from master do a
# make html and then push to remote:
# make clean
# git commit -a
# git checkout gh-pages
# git merge master
# make html
# git commit -a
# git push origin gh-pages
# git checkout master
# 

# Default target
all:

.PHONY: help list docs images extracts clean distclean


##
# Autoconf stuff
# Autoconf/configure is primarily for configuring the build of the
# Veil2 documentation.
#

include Makefile.global
include extracts.d

Makefile.global: ./configure
	./configure

./configure:
	autoconf



##
# PGXS stuff
#

EXTENSION = veil2
MODULE_big = veil2
SOURCES = src/veil2.c src/query.c
MODULEDIR = extension
VEIL2_LIB = $(addsuffix $(DLSUFFIX), veil2)

OBJS = $(SOURCES:%.c=%.o)
BITCODES = $(SOURCES:%.c=%.bc)

PG_CONFIG := $(shell ./find_pg_config)
PGXS := $(shell $(PG_CONFIG) --pgxs)
DATA = $(wildcard sql/veil2--*.sql)
TARGET_FILES := PG_CONFIG PG_VERSION $(OBJS) $(BITCODES) $(VEIL2_LIB)

include $(PGXS)


##
# Documention targets
#
# The documentation is constructed using docbook xml.  Much of the
# detailed documentation is extracted from the SQL source and
# converted into xml.  Also the dia ERD diagram is processed below so
# that each entity in the diagram is linked to the documentation for
# the table that implements it.
#
DOC_SOURCES := $(wildcard docs/*.xml) $(wildcard docs/parts/*.xml) 
BASE_STYLESHEET = $(DOCBOOK_STYLESHEETS)/html/chunkfast.xsl
VEIL2_STYLESHEET = docs/html_stylesheet.xsl
STYLESHEET_IMPORTER = docs/system-stylesheet.xsl
VERSION_FILE = docs/version.sgml
VERSION_NUMBER := $(shell cut -d" " -f1 VERSION)
HTMLDIR = html
TARGET_FILES += $(HTMLDIR)/* 
TARGET_DIRS += $(HTMLDIR)

INTERMEDIATE_FILES += $(STYLESHEET_IMPORTER) $(VERSION_FILE)

# Build the version entity for the docbook documentation.  This is
# included into the docbook source.
#
$(VERSION_FILE): VERSION configure
	@echo "Creating version entities for docs..."
	@{ \
	  echo "<!ENTITY version_number \"$(VERSION_NUMBER)\">"; \
	  echo "<!ENTITY version \"$(VEIL_VERSION)\">"; \
	  echo "<!ENTITY majorversion \"$(MAJOR_VERSION)\">"; \
	} > $@

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

# Extracts are extracts from sql files used to help build the
# documentation.  The dependencies here are many, somewhat complex and
# prone to changing, so we automate their generation using a script.
#
extracts.d: 
	@echo Recreating extracts dependency file $@...
	@echo "$@: `bin/extract_sql.sh -D docs docs/extracts`" >$@
	@bin/extract_sql.sh -d docs docs/extracts >>$@
	@echo "EXTRACTS := \
	    `bin/extract_sql.sh -d docs docs/extracts | \
	     cut -d: -f1 | xargs`" >>$@

INTERMEDIATE_FILES += extracts.d 

# Phony target for extracts - makes it easier to build for test and
# development purposes.
#
extracts: docs/extracts

# Use the extracts directory as a proxy for all extracts files.
# Recreate the extracts if the source $(DATA) has been modified.
docs/extracts: $(DATA)
	@echo Recreating sql extracts for docs...
	@[ -d docs/extracts ] || mkdir docs/extracts 
	@bin/extract_sql.sh docs docs/extracts
	@touch $@

TARGET_FILES += $(EXTRACTS) docs/extracts/*xml
TARGET_DIRS += docs/extracts

# Handle the generation of diagrams and coordinate maps.  Coordinate
# maps allow us to embed links from the entities in our ERD to the
# tables that implement those entities.
#
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
	echo XXXX $(DIAGRAMS_DIR)
	cp $< $@

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


# This builds a png files from .dia files.
#
%.png: %.dia
	@echo "Rebuilding $@ from $<..."
	dia --nosplash  --export=$*.eps $< 2>/dev/null
	pstoimg -antialias -transparent -crop tblr -scale 0.5 $*.eps
	@rm $*.eps



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


# The docs phony target ensures all html documentation targets are
# built, including the ERD diagram map.
#
docs: $(STYLESHEET_IMPORTER) $(VERSION_FILE) extracts \
	$(HTMLDIR)/index.html $(HTMLDIR)/mapped


##
# test targets
#

TESTDB := vpd

db:
	@if (psql -l | grep " $(TESTDB) " >/dev/null 2>&1); then \
	    echo "[database $(TESTDB) already exists]"; \
        else \
	    echo "Creating database $(TESTDB)..."; \
	    psql -c "create database $(TESTDB)"; \
	fi

drop:
	@if (psql -l | grep " $(TESTDB) " >/dev/null 2>&1); then \
	    echo "Dropping database $(TESTDB)..."; \
	    psql -c "drop database $(TESTDB)"; \
	fi

unit: db
	@echo "Performing unit tests..."
	@psql -X -v test=$(TEST) -f test/test_veil2.sql \
		-d $(TESTDB) 2>&1 | bin/pgtest_parser


##
# clean targets
#

# What constitutes general garbage files.
garbage_files := \\\#*  .\\\#*  *~ 
AUTOCONF_TARGETS := Makefile.global ./configure autom4te.cache \
		    config.log config.status

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
	echo Cleaning autoconf files...
	rm -rf $(AUTOCONF_TARGETS)


##
# help targets
#

# Provide a list of the targets buildable by this makefile.
list help:
	@echo "\n\
 Major targets for this makefile are:\n\n\
 help         - show this list of major targets\n\
 db           - build standalone '$(TESTDB)' database\n\
 drop         - drop standalone '$(TESTDB)' database\n\
 unit         - run unit tests (uses '$(TESTDB)' database, takes FLAGS variable)\n\
   test       - ditto (a synonym for unit)\n\
 docs         - create html documentation\n\
 images       - create all diagram images from sources\n\
 extracts     - create all doc extracts sql scripts\n\
 clean        - clean out unwanted files\n\
\n\
"
