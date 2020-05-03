<?xml version='1.0'?>
<!--
Custom docbook stylesheet for html for SAR docs.
-->

<xsl:stylesheet xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
                xmlns:saxon="http://icl.com/saxon"
                xmlns:lxslt="http://xml.apache.org/xslt"
                xmlns:redirect="http://xml.apache.org/xalan/redirect"
                xmlns:exsl="http://exslt.org/common"
                xmlns:doc="http://nwalsh.com/xsl/documentation/1.0"
		version="1.0"
                exclude-result-prefixes="saxon lxslt redirect exsl doc"
                extension-element-prefixes="saxon redirect lxslt exsl">

  <xsl:import href="system-stylesheet.xsl"/>

  <xsl:param name="custom.css.source">veil2.css.xml</xsl:param>

  <!-- Auto-generation of tables of contents -->
  <xsl:param name="generate.toc">
    set         toc
    article     toc
  </xsl:param>
  <xsl:param name="toc.max.depth">3</xsl:param>
  <xsl:param name="toc.section.depth">3</xsl:param>

  <!-- Add some sensible header stuff so that things size properly on 
       small screens.  -->
  <xsl:template name="system.head.content">
    <meta name="viewport" content="width=device-width, initial-scale=1"/>
  </xsl:template>

  
  <!-- Auto-numbering of sections -->
  <xsl:param name="section.autolabel" select="1"/>
  <xsl:param name="section.autolabel.max.depth" select="3"/>
  <xsl:param name="section.label.includes.component.label">1</xsl:param>
  <xsl:param name="chunk.section.depth" select="1"/>

  <!-- Template copied from inline.xsl and hacked to properly deal with
       strikethrough.  -->
  <xsl:template match="emphasis">
    <span>
      <xsl:call-template name="id.attribute"/>
      <xsl:choose>
	<!-- We don't want empty @class values, so do not propagate
	     empty @roles -->
	<xsl:when test="@role  and
			normalize-space(@role) != '' and
			$emphasis.propagates.style != 0">
          <xsl:apply-templates select="." mode="common.html.attributes">
            <xsl:with-param name="class" select="@role"/>
          </xsl:apply-templates>
	</xsl:when>
	<xsl:otherwise>
          <xsl:apply-templates select="." mode="common.html.attributes"/>
	</xsl:otherwise>
      </xsl:choose>
      <xsl:call-template name="anchor"/>
      
      <xsl:call-template name="simple.xlink">
	<xsl:with-param name="content">
          <xsl:choose>
            <xsl:when test="@role = 'bold' or @role='strong'">
              <!-- backwards compatibility: make bold into b elements, but -->
              <!-- don't put bold inside figure, example, or table titles -->
              <xsl:choose>
		<xsl:when test="local-name(..) = 'title'
				and (local-name(../..) = 'figure'
				or local-name(../..) = 'example'
				or local-name(../..) = 'table')">
                  <xsl:apply-templates/>
		</xsl:when>
		<xsl:otherwise>
                  <strong><xsl:apply-templates/></strong>
		</xsl:otherwise>
              </xsl:choose>
            </xsl:when>
	    <!-- Begin Marc's hack -->
            <xsl:when test="@role = 'strikethrough'">
              <del><xsl:apply-templates/></del>
            </xsl:when>
	    <!-- End Marc's hack -->
            <xsl:when test="@role and $emphasis.propagates.style != 0">
              <xsl:apply-templates/>
            </xsl:when>
            <xsl:otherwise>
              <em><xsl:apply-templates/></em>
            </xsl:otherwise>
          </xsl:choose>
	</xsl:with-param>
      </xsl:call-template>
    </span>
  </xsl:template>

  <!-- Hack of header.navigation template from chunk-common.xsl
       This gives us the full set of of navigation options in the header.-->
  <xsl:template name="header.navigation">
    <xsl:param name="prev" select="/foo"/>
    <xsl:param name="next" select="/foo"/>
    <xsl:param name="nav.context"/>
    
    <xsl:variable name="home" select="/*[1]"/>
    <xsl:variable name="up" select="parent::*"/>
    
    <xsl:variable name="row1" select="$navig.showtitles != 0"/>
    <xsl:variable name="row2" select="count($prev) &gt; 0
                                      or (count($up) &gt; 0 
                                      and generate-id($up) != generate-id($home)
                                      and $navig.showtitles != 0)
                                      or count($next) &gt; 0"/>

    <xsl:if test="$suppress.navigation = '0' and $suppress.header.navigation = '0'">
      <div class="navheader">
	<xsl:if test="$row1 or $row2">
          <table width="100%" summary="Navigation header">
	    <xsl:if test="$row1">
              <tr>
		<td width="40%" align="{$direction.align.start}">
                  <xsl:if test="count($prev)>0">
                    <a accesskey="p">
                      <xsl:attribute name="href">
			<xsl:call-template name="href.target">
                          <xsl:with-param name="object" select="$prev"/>
			</xsl:call-template>
                      </xsl:attribute>
                      <xsl:call-template name="navig.content">
			<xsl:with-param name="direction" select="'prev'"/>
                      </xsl:call-template>
                    </a>
                  </xsl:if>
                  <xsl:text>&#160;</xsl:text>
		</td>
		<td width="20%" align="center">
                  <xsl:choose>
                    <xsl:when test="count($up)&gt;0
                                    and generate-id($up) != generate-id($home)">
                      <a accesskey="u">
			<xsl:attribute name="href">
                          <xsl:call-template name="href.target">
                            <xsl:with-param name="object" select="$up"/>
                          </xsl:call-template>
			</xsl:attribute>
			<xsl:call-template name="navig.content">
                          <xsl:with-param name="direction" select="'up'"/>
			</xsl:call-template>
                      </a>
                    </xsl:when>
                    <xsl:otherwise>&#160;</xsl:otherwise>
                  </xsl:choose>
		</td>
		<td width="40%" align="{$direction.align.end}">
                  <xsl:text>&#160;</xsl:text>
                  <xsl:if test="count($next)>0">
                    <a accesskey="n">
                      <xsl:attribute name="href">
			<xsl:call-template name="href.target">
                          <xsl:with-param name="object" select="$next"/>
			</xsl:call-template>
                      </xsl:attribute>
                      <xsl:call-template name="navig.content">
			<xsl:with-param name="direction" select="'next'"/>
                      </xsl:call-template>
                    </a>
                  </xsl:if>
		</td>
              </tr>
            </xsl:if>
	    
            <xsl:if test="$row2">
              <tr>
		<td width="40%" align="{$direction.align.start}" valign="top">
                  <xsl:if test="$navig.showtitles != 0">
                    <xsl:apply-templates select="$prev" mode="object.title.markup"/>
                  </xsl:if>
                  <xsl:text>&#160;</xsl:text>
		</td>
		<td width="20%" align="center">
                  <xsl:choose>
                    <xsl:when test="$home != . or $nav.context = 'toc'">
                      <a accesskey="h">
			<xsl:attribute name="href">
                          <xsl:call-template name="href.target">
                            <xsl:with-param name="object" select="$home"/>
                          </xsl:call-template>
			</xsl:attribute>
			<xsl:call-template name="navig.content">
                          <xsl:with-param name="direction" select="'home'"/>
			</xsl:call-template>
                      </a>
                      <xsl:if test="$chunk.tocs.and.lots != 0 and $nav.context != 'toc'">
			<xsl:text>&#160;|&#160;</xsl:text>
                      </xsl:if>
                    </xsl:when>
                    <xsl:otherwise>&#160;</xsl:otherwise>
                  </xsl:choose>
		  
                  <xsl:if test="$chunk.tocs.and.lots != 0 and $nav.context != 'toc'">
                    <a accesskey="t">
                      <xsl:attribute name="href">
			<xsl:value-of select="$chunked.filename.prefix"/>
			<xsl:apply-templates select="/*[1]"
                                             mode="recursive-chunk-filename">
                          <xsl:with-param name="recursive" select="true()"/>
			</xsl:apply-templates>
			<xsl:text>-toc</xsl:text>
			<xsl:value-of select="$html.ext"/>
                      </xsl:attribute>
                      <xsl:call-template name="gentext">
			<xsl:with-param name="key" select="'nav-toc'"/>
                      </xsl:call-template>
                    </a>
                  </xsl:if>
		</td>
		<td width="40%" align="{$direction.align.end}" valign="top">
                  <xsl:text>&#160;</xsl:text>
                  <xsl:if test="$navig.showtitles != 0">
                    <xsl:apply-templates select="$next" mode="object.title.markup"/>
                  </xsl:if>
		</td>
              </tr>
            </xsl:if>
	    
          </table>
	</xsl:if>
	<xsl:if test="$header.rule != 0">
          <hr/>
	</xsl:if>
      </div>
    </xsl:if>
  </xsl:template>

</xsl:stylesheet>

