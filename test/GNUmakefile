# ----------
# GNUmakefile
#
#      Copyright (c) 2020 Marc Munro
#      Author:  Marc Munro
#      License: GPL V3
#
# ----------
#
# The purpose of this is to run make in the parent directory.  This
# allows make to be run anywhere in the directory tree and also allows
# emacs' make and next-error to work properly from any directory.

all:

%::
	cd ..; $(MAKE) MAKEFLAGS="$(MAKEFLAGS)" $@
