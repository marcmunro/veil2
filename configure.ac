#
#      Autoconf input file for veil2
#
#      Copyright (c) 2020 Marc Munro
#      Author:  Marc Munro
#      License: GPL V3
#

m4_define([VEIL2_VERSION],
   esyscmd([cat VERSION]))

AC_INIT([veil2], VEIL2_VERSION, [marc@bloodnok.com])

AC_CONFIG_FILES([Makefile.global])

AC_SUBST(MAJOR_VERSION, esyscmd([cat VERSION | \
            cut -d\" -f2 | cut -d. -f1 | tr -d '\n']))
AC_SUBST(MINOR_VERSION, esyscmd([cat VERSION | \
            cut -d\" -f2 | cut -d. -f2 | cut -d\  -f1 | tr -d '\n']))

# Check for xslt - needed to build html docs
AC_CHECK_PROGS(XSLTPROC, xsltproc)

dnl Find docbook entities file
AC_DEFUN([VEIL_PATH_DOCBOOK_ENTITIES],
[AC_ARG_VAR(DOCBOOKENT, [location of Docbook entities])
AC_MSG_CHECKING([for DocBook entities])
AC_CACHE_VAL([pgac_cv_path_entities],
[if test -n "$DOCBOOKENT"; then
  veil_path=$DOCBOOKENT
else
  for veil_prefix in /usr /usr/local /opt /sw; do
    for veil_infix in share lib; do
      for veil_postfix in \
        xml/docbook/schema/dtd/4.5 \
	sgml/docbook/dtd/4.5 \
	sgml/docbook/xml-dtd-4.5
      do
        veil_candidate=$veil_prefix/$veil_infix/$veil_postfix
        if test -r "$veil_candidate/dbcentx.mod" 
        then
          veil_path=$veil_candidate/dbcentx.mod
          break 3
        fi
      done
    done
  done
fi])

DOCBOOKENT=$veil_path

AC_SUBST([DOCBOOKENT])
if test -n "$DOCBOOKENT"; then
  AC_MSG_RESULT([$DOCBOOKENT])
else
  AC_MSG_RESULT(no)
fi])

dnl Find docbook fastchunk stylesheet
AC_DEFUN([VEIL_PATH_DOCBOOK_STYLESHEETS],
[AC_ARG_VAR(DOCBOOKSS, [location of Docbook stylesheet])
AC_MSG_CHECKING([for DocBook stylesheet])
AC_CACHE_VAL([pgac_cv_path_entities],
[if test -n "$DOCBOOKSS"; then
  veil_path=$DOCBOOKSS
else
  for veil_prefix in /usr /usr/local /opt /sw; do
    for veil_infix in share lib; do
      for veil_postfix in \
        xml/docbook/stylesheet/docbook-xsl \
	sgml/docbook/stylesheet/docbook-xsl 
      do
        veil_candidate=$veil_prefix/$veil_infix/$veil_postfix
        if test -r "$veil_candidate/xhtml/chunk.xsl" 
        then
          veil_path=$veil_candidate
          break 3
        fi
      done
    done
  done
fi])

DOCBOOKSS=$veil_path

AC_SUBST([DOCBOOKSS])
if test -n "$DOCBOOKSS"; then
  AC_MSG_RESULT([$DOCBOOKSS])
else
  AC_MSG_RESULT(no)
fi])


VEIL_PATH_DOCBOOK_ENTITIES
VEIL_PATH_DOCBOOK_STYLESHEETS


AC_OUTPUT
