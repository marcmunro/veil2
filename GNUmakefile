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
# TODO: Improve/rewrite comments in here.
#       Update help target for new stuff
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

.PHONY: help list docs deps images extracts clean distclean doxygen


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

# What constitutes general garbage files.
garbage_files := \\\#*  .\\\#*  *~ 
AUTOCONF_TARGETS := Makefile.global ./configure autom4te.cache \
		    config.log config.status


##
# C Language building stuff
#
SOURCES = $(wildcard src/*.c)
HEADERS = $(wildcard src/*.h)
OBJS = $(SOURCES:%.c=%.o)
DEPS = $(SOURCES:%.c=%.d)
BITCODES = $(SOURCES:%.c=%.bc)

INTERMEDIATE_FILES += $(DEPS) $(BITCODES) $(OBJS)

##
# PGXS stuff
#

EXTENSION = veil2
MODULE_big = veil2
MODULEDIR = extension
VEIL2_LIB = $(addsuffix $(DLSUFFIX), veil2)

PG_CONFIG := $(shell ./find_pg_config)
PGXS := $(shell $(PG_CONFIG) --pgxs)
DATA = $(wildcard sql/veil2--*.sql)

TARGET_FILES := PG_CONFIG PG_VERSION $(OBJS) $(VEIL2_LIB)

include $(PGXS)


# Hmmmm.  This appears necessary.  It wasn't needed before I added
# the deps handling stuff so this is a bit baffling.  Does no harm
# tho'.
all: $(VEIL2_LIB)

$(VEIL2_LIB): $(OBJS)

# Build per-source dependency files for inclusion
# This ignores header files and any other non-local files (such as
# postgres include files).  
%.d: %.c
	@echo Recreating $@
	@$(SHELL) -ec "$(CC) -MM -MT $*.o $(CPPFLAGS) $< | \
		xargs -n 1 | grep '^[^/]' | \
		sed -e '1,$$ s/$$/ \\\\/' -e '$$ s/ \\\\$$//' \
		    -e '2,$$ s/^/  /' | \
		sed 's!$*.o!& $@!g'" > $@

# Target used by recursive call from deps target below.  
make_deps: $(DEPS)
	@>/dev/null # Prevent the 'Nothing to be done for...' msg

# Target that rebuilds all dep files unconditionally.  
deps: 
	rm -f $(DEPS)
	$(MAKE) MAKEFLAGS="$(MAKEFLAGS)" make_deps

include $(DEPS)


##
# Documention targets
#
# The primary documentation is constructed using docbook xml.  Much of
# the detailed documentation is extracted from the SQL source and
# converted into xml.  Also the dia ERD diagram is processed below so
# that each entity in the diagram is linked to the documentation for
# the table that implements it.  There is also Doxygen documentation
# generated from the C sources.
#
DOC_SOURCES := $(wildcard docs/*.xml) $(wildcard docs/parts/*.xml) 
BASE_STYLESHEET = $(DOCBOOK_STYLESHEETS)/html/chunkfast.xsl
VEIL2_STYLESHEET = docs/html_stylesheet.xsl
STYLESHEET_IMPORTER = docs/system-stylesheet.xsl
VERSION_FILE = docs/version.sgml
VERSION_NUMBER := $(shell cut -d" " -f1 VERSION)
HTMLDIR = html
ANCHORS_DIR = docs/anchors
TARGET_FILES += $(HTMLDIR)/* doxy.tag $(ANCHORS_DIR)/* \
		$(HTMLDIR)/doxygen/html/search/* \
		$(HTMLDIR)/doxygen/html/* $(HTMLDIR)/doxygen/*

TARGET_DIRS += $(HTMLDIR)/doxygen/html/search $(HTMLDIR)/doxygen/html \
	       $(HTMLDIR)/doxygen $(HTMLDIR) $(ANCHORS_DIR)

INTERMEDIATE_FILES += $(STYLESHEET_IMPORTER) $(VERSION_FILE)

# Create doxygen-based docs for the C-language stuff.  We use the
# doxygen tag file as a proxy for the output document set.
#
doxy.tag: $(SOURCES) $(HEADERS)
	mkdir -p $(HTMLDIR)//doxygen 2>/dev/null
	doxygen docs/Doxyfile || \
	    (echo "Doxygen fails: is it installed?"; exit 2)

$(ANCHORS_DIR): doxy.tag $(DOC_SOURCES) 
	@echo "Recreating doxygen anchor files..."
	@mkdir -p $(ANCHORS_DIR)
	@bin/get_doxygen_anchors.sh doxy.tag docs $(ANCHORS_DIR)

doxygen: doxy.tag $(ANCHORS_DIR)
	@>/dev/null # Prevent the 'Nothing to be done for...' msg



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
		 $(STYLESHEET_IMPORTER) $(TARGET_IMAGES) $(EXTRACTS) \
		 $(ANCHORS_DIR)
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
	$(HTMLDIR)/index.html $(HTMLDIR)/mapped doxygen 


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

SUBDIRS = src docs/parts docs demo bin

# Clean target that does not conflict with the same target from PGXS
local_clean:
	@rm -f $(garbage_files) 2>/dev/null || true
	@echo $(SUBDIRS)
	@for i in $(SUBDIRS); do \
	   echo Cleaning $${i}...; \
	   (cd $${i}; rm -f $(garbage_files)); \
	done || true
	echo Cleaning intermediate and target files...
	@rm -f $(INTERMEDIATE_FILES) $(TARGET_FILES) 2>/dev/null || true
	@rmdir $(TARGET_DIRS) 2>/dev/null || true

# Make PGXS clean target use our cleanup target.
clean: local_clean

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
 help      - show this list of major targets\n\
 db        - build standalone '$(TESTDB)' database\n\
 deps      - Recreate the xxx.d dependency files\n\
 drop      - drop standalone '$(TESTDB)' database\n\
 unit      - run unit tests (uses '$(TESTDB)' database, takes FLAGS variable)\n\
 test      - ditto (a synonym for unit)\n\
 docs      - create html documentation (including doxygen docs\n\
 doxygen   - create doxygen html documentation only\n\
 images    - create all diagram images from sources\n\
 extracts  - create all doc extracts sql scripts\n\
 clean     - clean out unwanted files\n\
\n\
"
