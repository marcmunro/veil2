<?xml version='1.0'?>
<!--

      Copyright (c) 2020 Marc Munro
      Author:  Marc Munro
      License: GPL V3

Stylesheet for extracting position information from Dia files of
Marc's pretty ERDs.  This is to enable the creation of map files from
diagrams, so that we can use a diagram as an interface into a data
dictionary.

The output from using this stylesheet is a bunch of points and a bunch
of entity definitions.  From these, and the size of image, we can work
out our scaling factor and thereby define polygons for a map.
-->

<xsl:stylesheet
    version="1.0"
    xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
    xmlns:exsl="http://exslt.org/common"
    xmlns:dia="http://www.lysator.liu.se/~alla/dia/"
    exclude-result-prefixes="dia">

  <xsl:template match="text()"/>  <!-- Ignore text nodes.  -->

  <!-- Match root node and return a root element to make xmllint happy. -->
  <xsl:template match="dia:diagram">
    <diagram>
      <xsl:apply-templates/>

      <!-- Now get every position from the file.  This will help us
	   figure out the x and y grid range. -->
      <xsl:for-each select="//dia:point">
	<point>
	  <xsl:attribute name="x">
	    <xsl:value-of select="substring-before(@val, ',')"/>
	  </xsl:attribute>
	  <xsl:attribute name="y">
	    <xsl:value-of select="substring-after(@val, ',')"/>
	  </xsl:attribute>
	</point>
      </xsl:for-each>
    </diagram>
  </xsl:template>

  <!-- Scan through all otherwise unhandled elements.  -->
  <xsl:template match="*">
    <xsl:apply-templates/>
  </xsl:template>

  <!-- Recursively copy elements. -->
  <xsl:template match="*" mode="copy">
    <xsl:copy>
      <xsl:copy-of select="@*"/>
      <xsl:apply-templates mode="copy"/>
    </xsl:copy>
  </xsl:template>

  <!-- Get a dia objectnode based on its id. -->
  <xsl:template name="get-objnode">
    <xsl:param name="objid"/>
    <xsl:param name="type"/>
    <xsl:for-each select="//dia:object[@id = $objid and @type=$type]">
      <object>
	<xsl:copy-of select="@*"/>
	<xsl:apply-templates mode="copy"/>
      </object>
    </xsl:for-each>
  </xsl:template>  

  <!-- Match and process string elements. -->
  <xsl:template match="dia:object[@type='Standard - Text']">
    <refobject>
      <xsl:copy-of select="@id"/>
      <xsl:attribute name="value">
	<xsl:value-of select="substring-before(
			        substring-after(
                                  descendant::dia:string/text(), '#'),
                                '#')"/>
      </xsl:attribute>
      <xsl:for-each select="descendant::dia:connection">
	<xsl:variable name="box">
	  <xsl:call-template name="get-objnode">
	    <xsl:with-param name="objid">
	      <xsl:value-of select="@to"/>
	    </xsl:with-param>
	    <xsl:with-param name="type">
	      <xsl:value-of select="'Standard - Box'"/>
	    </xsl:with-param>
	  </xsl:call-template>
	</xsl:variable>
	<xsl:for-each select="exsl:node-set($box)//dia:attribute">
	  <xsl:if test="@name='obj_pos'">
	    <xsl:attribute name="pos">
	      <xsl:value-of select="dia:point/@val"/>
	    </xsl:attribute>
	  </xsl:if>
	  <xsl:if test="@name='obj_bb'">
	    <!-- Coords are given in terms of grid lines starting at
		 top left.   Coords are 4 values.  left line x-pos,
		 top-line y pos, right line x-pos, bottom line
		 y-pos.  For map purposes we will need the four
		 values split out.  -->
	    <top-left>
	      <xsl:attribute name="x">
		<xsl:value-of
		    select="substring-before(
                               substring-before(dia:rectangle/@val, ';'),
			       ',')"/>
	      </xsl:attribute>
	      <xsl:attribute name="y">
		<xsl:value-of
		    select="substring-after(
                               substring-before(dia:rectangle/@val, ';'),
			       ',')"/>
	      </xsl:attribute>
	    </top-left>
	    <bottom-right>
	      <xsl:attribute name="x">
		<xsl:value-of
		    select="substring-before(
                               substring-after(dia:rectangle/@val, ';'),
			       ',')"/>
	      </xsl:attribute>
	      <xsl:attribute name="y">
		<xsl:value-of
		    select="substring-after(
                               substring-after(dia:rectangle/@val, ';'),
			       ',')"/>
	      </xsl:attribute>
	    </bottom-right>
	  </xsl:if>
	</xsl:for-each>
      </xsl:for-each>
    </refobject>
  </xsl:template>

 
</xsl:stylesheet>
