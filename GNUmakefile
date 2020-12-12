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
# so that the diagrams can be used to navigate to entity descriptions,
# and also to create automated documentation from the sql scripts.
# The GNUmakefiles in subdirectories are just there to automatically
# invoke this makefile in such a way that make can be invoked from
# those subdirectories, and emacs' compile and next-error handling
# will still work if you are not in the root directory.

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
# make docs
# git commit -a
# git push origin gh-pages
# git checkout master
# 

# Default target
all:

# Phony targets.  These do not match filenames and must always be
# executed even if a file of the same name exists and appears to be up
# to date.
.PHONY: all make_deps deps install install-doc-tree \
	doxygen extracts images docs docs_clean \
	db drop unit \
	check_meta check_branch check_tag check_docs \
	check_commit check_origin \
	zipfile do_zipfile mostly_clean distclean list help

# What constitutes general garbage files.
garbage_files := \\\#*  .\\\#*  *~ 


##
# Autoconf stuff
# Autoconf/configure is primarily for configuring the build of the
# Veil2 documentation.
#
include Makefile.global
include extracts.d

Makefile.global: ./configure Makefile.global.in
	./configure

./configure:
	autoconf

AUTOCONF_TARGETS := Makefile.global ./configure autom4te.cache \
		    config.log config.status

##
# C Language stuff
#
HEADERS = $(wildcard src/*.h)
SOURCES = $(wildcard src/*.c)
OBJS = $(SOURCES:%.c=%.o)
DEPS = $(SOURCES:%.c=%.d)

# These files may be automatically created by compilation.  If they
# are, we need to be able to clean them up, hence the defiinition
# here.  We do not need the definition for any other purpose.
BITCODES = $(SOURCES:%.c=%.bc)

INTERMEDIATE_FILES += $(DEPS) $(BITCODES) $(OBJS)

# These definitions are needed in order to publish the docs and data
# dirs from veil2 functions.  
PG_CFLAGS = -D DATA_PATH=\"$(DESTDIR)$(datadir)/$(datamoduledir)\" \
	    -D DOCS_PATH=\"$(DESTDIR)$(docdir)/$(docmoduledir)\" 

# This allows us to use pgbitmap utility functions.
SHLIB_LINK = $(DESTDIR)$(pkglibdir)/pgbitmap.so

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
# PGXS stuff
#

EXTENSION = veil2 veil2_demo
MODULE_big = veil2
MODULEDIR = veil2
VEIL2_LIB = $(addsuffix $(DLSUFFIX), veil2)

PG_CONFIG := $(shell bin/find_pg_config)
PGXS := $(shell $(PG_CONFIG) --pgxs)
DATA = $(wildcard sql/veil2--*.sql) $(wildcard demo/*.sql) 
# This is for installing documentation.  We cannot just use DOCS as
# install will flatten the directory hierarchy and result in the
# installed documentation being useless.  See the install-doc-tree
# target below.
HTMLDIR = html
DOCS_TREE = $(HTMLDIR)

TARGET_FILES := PG_CONFIG PG_VERSION $(OBJS) $(VEIL2_LIB)

include $(PGXS)

# Add the install-data-tree target to the standard install target.
# This is for installing documentation as an html documentation tree.
install: install-doc-tree

# Install the contents of DOCS_TREE into the appropriate docs
# directory.  Some of the variables below are defined in the pgxs
# makefile. 
install-doc-tree: 
	@echo INSTALLING LOCAL DOCS
	@if [ -d $(HTMLDIR) ]; then \
	    find $(DOCS_TREE) -type f -exec \
	        install -vDm 755 {} $(DESTDIR)$(docdir)/$(docmoduledir)/{} \; \
	; fi


##
# Documention targets
#
# The primary documentation is constructed using docbook xml.  Much of
# the detailed documentation is extracted from the SQL source and
# converted into xml.  Also, dia diagrams are processed below so that
# each entity/view in the diagram is linked to the documentation for
# the table/dbobject that implements it.  There is also Doxygen
# documentation generated from the C sources.
#
DOC_SOURCES := $(wildcard docs/*.xml) $(wildcard docs/parts/*.xml) 
BASE_STYLESHEET = $(DOCBOOK_STYLESHEETS)/html/chunkfast.xsl
VEIL2_STYLESHEET = docs/html_stylesheet.xsl
STYLESHEET_IMPORTER = docs/system-stylesheet.xsl
VERSION_FILE = docs/version.sgml
VERSION_NUMBER := $(shell cut -d" " -f1 VERSION)
ANCHORS_DIR = docs/anchors
DOCS_TARGET_FILES += $(HTMLDIR)/* doxy.tag $(ANCHORS_DIR)/* \
		     $(HTMLDIR)/doxygen/html/search/* \
		     $(HTMLDIR)/doxygen/html/* $(HTMLDIR)/doxygen/*

DOCS_TARGET_DIRS += $(HTMLDIR)/doxygen/html/search $(HTMLDIR)/doxygen/html \
	       	    $(HTMLDIR)/doxygen $(HTMLDIR) $(ANCHORS_DIR)

DOCS_INTERMEDIATE_FILES += $(STYLESHEET_IMPORTER) $(VERSION_FILE)

# Create doxygen-based docs for the C-language stuff.  We use the
# doxygen tag file as a proxy for the output document set.
#
doxy.tag: $(SOURCES) $(HEADERS)
	mkdir -p $(HTMLDIR)//doxygen 2>/dev/null
	doxygen docs/Doxyfile || \
	    (echo "Doxygen fails: is it installed?"; exit 2)

# This provides usable links into the Doxygen documentation from the
# docbook documentation.
$(ANCHORS_DIR): doxy.tag $(DOC_SOURCES) 
	@echo "Recreating doxygen anchor files..."
	@mkdir -p $(ANCHORS_DIR)
	@bin/get_doxygen_anchors.sh doxy.tag docs $(ANCHORS_DIR)
	@touch $(ANCHORS_DIR)

# You can make just the doxygen docs using this target.
doxygen: doxy.tag $(ANCHORS_DIR)
	@mkdir -p $(HTMLDIR)//doxygen 2>/dev/null
	@cp LICENSE $(HTMLDIR)/doxygen

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

DOCS_INTERMEDIATE_FILES += extracts.d 

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

$(EXTRACTS): docs/extracts

DOCS_TARGET_FILES += $(EXTRACTS) docs/extracts/*xml
DOCS_TARGET_DIRS += docs/extracts

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
DOCS_INTERMEDIATE_FILES += $(DIAGRAM_INTERMEDIATES)

TARGET_IMAGES := $(patsubst $(DIAGRAMS_DIR)%, $(HTMLDIR)%, $(DIAGRAM_IMAGES))


# Copy new images to html dir
#
$(HTMLDIR)/%.png: diagrams/%.png
	@-mkdir -p $(HTMLDIR) 2>/dev/null
	cp $< $@

$(HTMLDIR)/veil2_erd.png: diagrams/veil2_erd.png
$(HTMLDIR)/veil2_views.png: diagrams/veil2_views.png

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
%.map: %.coords %.png 
	@mkdir -p $(HTMLDIR) 2>/dev/null
	@echo Creating HTML map file $@...
	bin/erd2map $* $(HTMLDIR) >$*.map

diagrams/veil2_views.map: diagrams/veil2_views.coords \
			  diagrams/veil2_views.png 
	@echo Creating HTML map file $@...
	bin/erd2map -v diagrams/veil2_views $(HTMLDIR) view >$@

# Phony target for building image files.
#
images: $(DIAGRAM_IMAGES)

# This builds .png files from .dia files.
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
	@echo $(TARGET_IMAGES)
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

docs_clean:
	echo Cleaning docs intermediate and target files...
	@rm -f $(DOCS_INTERMEDIATE_FILES) \
	       $(DOCS_TARGET_FILES) 2>/dev/null || true
	@rm -rf $(DOCS_TARGET_DIRS) 2>/dev/null || true


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
# release targets
#
ZIPFILE_BASENAME = veil2-$(VERSION_NUMBER)
ZIPFILENAME = $(ZIPFILE_BASENAME).zip
ONLINE_DOCS = https://marcmunro.github.io/veil2/html/index.html
GIT_UPSTREAM = github origin

# Ensure that we are in the master git branch
check_branch:
	@[ `git rev-parse --abbrev-ref HEAD` = master ] || \
	    (echo "    CURRENT GIT BRANCH IS NOT MASTER" 1>&2 && exit 2)

# Check that our metadata file for pgxs is up to date.  This is very
# simplistic but aimed only at ensuring you haven't forgotten to
# update the file.
check_meta: META.json
	@grep '"version"' META.json | head -2 | cut -d: -f2 | \
	    tr -d '",' | \
	    while read a; do \
	      	[ "x$$a" = "x$(VERSION_NUMBER)" ] || \
		  (echo "    INCORRECT VERSION ($$a) IN META.json"; exit 2); \
	    done
	@grep '"file"' META.json | cut -d: -f2 | tr -d '",' | \
	    while read a; do \
	      	[ "x$$a" = "xveil2--$(VERSION_NUMBER).sql" ] || \
		  (echo "    INCORRECT FILE NAME ($$a) IN META.json"; exit 2); \
	    done

# Check that head has been tagged.  We assume that if it has, then it
# has been tagged correctly.
check_tag:
	@tag=`git tag --points-at HEAD`; \
	if [ "x$${tag}" = "x" ]; then \
	    echo "    NO GIT TAG IN PLACE"; \
	    exit 2; \
	fi

# Check that the latest docs have been published.
check_docs: docs
	@[ "x`cat html/index.html | md5sum`" = \
	   "x`curl -s $(ONLINE_DOCS) | md5sum`" ] || \
	    (echo "    LATEST DOCS NOT PUBLISHED"; exit 2)

# Check that there are no uncomitted changes.
check_commit:
	@git status -s | wc -l | grep '^0$$' >/dev/null || \
	    (echo "    UNCOMMITTED CHANGES FOUND"; exit 2)

# Check that we have pushed the latest changes
check_origin:
	@err=0; \
	 for origin in $(GIT_UPSTREAM); do \
	    git diff --quiet master $${origin}/master 2>/dev/null || \
	    { echo "    UNPUSHED UPDATES FOR $${origin}"; \
	      err=2; }; \
	done; exit $$err

# Check that this version appears in the change history
check_history:
	@grep "<entry>$(VERSION_NUMBER)" \
	    docs/parts/change_history.xml >/dev/null || \
	    (echo "    CURRENT VERSION NOT RECORDED IN CHANGE HISTORY"; \
	     exit 2)

# Check that the correct version is recorded in the control file
check_control:
	@grep "version.*$(VERSION_NUMBER)" \
	    veil2.control >/dev/null || \
	    (echo "    INCORRECT VERSION IN veil2.control"; \
	     exit 2)

# Check that the correct version is recorded in the demo control file
check_demo_control:
	@grep "version.*$(VERSION_NUMBER)" \
	    veil2_demo.control >/dev/null || \
	    (echo "    INCORRECT VERSION IN veil2_demo.control"; \
	     exit 2)


# Create a zipfile for release to pgxn, but only if everthing is ready
# to go.  Note that we distribute our dependencies in case our user is
# going to build things manually and can't build them themselves, and
# our built docs as we don't require users to have a suitable build
# environment for building them themselves, and having the docs
# installed locally is a good thing.
zipfile: 
	@$(MAKE) -k --no-print-directory \
	    check_branch check_meta check_tag check_docs \
	    check_commit check_origin check_history \
	    check_control check_demo_control 2>&1 | \
	    bin/makefilter 1>&2
	@$(MAKE) do_zipfile

do_zipfile: mostly_clean deps
	git archive --format zip --prefix=$(ZIPFILE_BASENAME)/ \
	    --output $(ZIPFILENAME) master

TARGET_FILES += $(ZIPFILENAME)


##
# clean targets
#

SUBDIRS = src docs/parts docs demo bin sql

# Clean target that does not conflict with the same target from PGXS
mostly_clean:
	@rm -f $(garbage_files) 2>/dev/null || true
	@echo $(SUBDIRS)
	@for i in $(SUBDIRS); do \
	   echo Cleaning $${i}...; \
	   (cd $${i}; rm -f $(garbage_files)); \
	done || true
	@rm -f $(INTERMEDIATE_FILES) $(TARGET_FILES) 2>/dev/null || true
	@rm -rf $(TARGET_DIRS) 2>/dev/null || true

# Make PGXS clean target use our cleanup targets.
clean: mostly_clean docs_clean

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
 zipfile   - create a zipfile for release to PGXN\n\
 clean     - clean out unwanted files\n\
\n\
"
