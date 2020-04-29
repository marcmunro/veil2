# GNUmakefile
#
#      Main Makefile for veil2
#
#      Copyright (c) 2020 Marc Munro
#      Author:  Marc Munro
#      License: BSD
#
# For a list of targets use make help.
# 

.PHONY: db drop clean list help unit check test

all: db

db:
	@if (psql -l | grep vpd >/dev/null 2>&1); then \
	    echo "[database already exists]"; \
        else \
	    echo "Creating database..."; \
	    psql -f sql/create_vpd.sql; \
	fi

drop:
	@psql -c "drop database vpd"
	@psql -c "drop role veil_user"

# You can run this using several target names.  It requires the VPD
# database to exist and will create it if necessary.
# TODO: COMMENT THIS: The grep below is used to eliminate lines...
unit check test: db
	@echo "Performing unit tests..."
	@psql -v flags=$(FLAGS) -f test/test_veil2.sql -d vpd | grep -v '^##'


# Provide a list of the targets buildable by this makefile.
list help:
	@echo "\n\
 Major targets for this makefile are:\n\n\
 dp           - build standalone VPD database\n\
 drop         - drop standalone VPD database\n\
 clean        - clean out unwanted files\n\
 unit         - run unit tests (uses VPD database, takes FLAGS variable)\n\
 help         - show this list of major targets\n\
\n\
"
