<?xml version='1.0'?>
<!--
Custom docbook stylesheet for html for Veil2 docs.
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
    book     toc,title
    part     toc,title
  </xsl:param>
  <xsl:param name="toc.max.depth">2</xsl:param>
  <xsl:param name="toc.section.depth">2</xsl:param>

  <!-- Auto-numbering of sections -->
  <xsl:param name="section.autolabel" select="1"/>
  <xsl:param name="section.autolabel.max.depth" select="3"/>
  <xsl:param name="section.label.includes.component.label">1</xsl:param>
  <xsl:param name="chunk.section.depth" select="0"/>

  <!-- Easier to read html -->
  <xsl:param name="chunker.output.indent" select="'yes'"/>
  <xsl:param name="chunker.output.encoding">UTF-8</xsl:param>
  
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

  <xsl:template match="processing-instruction('sql-definition')">
    <xsl:variable name="filename">
      <xsl:value-of select="concat('extracts/',
                                   substring-before(., ' '), 
			           '_',
			            substring-before(
                                        substring-after(., ' '), 
                                        ' '),
				   '.xml')"/>
    </xsl:variable>
    <xsl:apply-templates select="document($filename)/extract/*"/>
  </xsl:template>

  <xsl:template match="processing-instruction('doxygen-ulink')">
    <xsl:variable name="type">
      <xsl:value-of select="substring-before(., ' ')"/>
    </xsl:variable>
    <xsl:variable name="name">
      <xsl:value-of select="substring-before(
			        substring-after(., ' '),
				' ')"/>
    </xsl:variable>
    <xsl:variable name="content">
      <xsl:value-of select="substring-after(
			        substring-after(., ' '),
				' ')"/>
    </xsl:variable>
    <xsl:variable name="anchorfile">
      <!-- Read the anchorfile -->
      <xsl:value-of select="document(concat('anchors/', $type, '_',
	                                     $name, '.anchor'))"/>
    </xsl:variable>
    <!-- Create the link to the anchor -->
    <a class="ulink"
       target="_top"
       href="{concat('doxygen/html/', $anchorfile)}">
      <xsl:value-of select="$content"/>
    </a>
  </xsl:template>


  <!-- MM: The following hack is to ensure a DOCTYPE header in each
       chunk.  There ought to be a better way to do this but I haven't
       found it.  Template copied from chunk-common.xsl -->
  <xsl:template name="process-chunk">
    <xsl:param name="prev" select="."/>
    <xsl:param name="next" select="."/>
    <xsl:param name="content">
      <xsl:apply-imports/>
    </xsl:param>
    
    <xsl:variable name="ischunk">
      <xsl:call-template name="chunk"/>
    </xsl:variable>
  
    <xsl:variable name="chunkfn">
      <xsl:if test="$ischunk='1'">
	<xsl:apply-templates mode="chunk-filename" select="."/>
      </xsl:if>
    </xsl:variable>

    <xsl:if test="$ischunk='0'">
      <xsl:message>
	<xsl:text>Error </xsl:text>
	<xsl:value-of select="name(.)"/>
	<xsl:text> is not a chunk!</xsl:text>
      </xsl:message>
    </xsl:if>

    <xsl:variable name="filename">
      <xsl:call-template name="make-relative-filename">
	<xsl:with-param name="base.dir" select="$chunk.base.dir"/>
	<xsl:with-param name="base.name" select="$chunkfn"/>
      </xsl:call-template>
    </xsl:variable>

    <xsl:call-template name="write.chunk">
      <xsl:with-param name="filename" select="$filename"/>
      <xsl:with-param name="content">
	<!-- MM's hack begins. -->
	<xsl:text disable-output-escaping="yes">&lt;!DOCTYPE html&gt;&#x0a;</xsl:text>
	<!-- MM's hack ends. -->
	<xsl:call-template name="chunk-element-content">
          <xsl:with-param name="prev" select="$prev"/>
          <xsl:with-param name="next" select="$next"/>
          <xsl:with-param name="content" select="$content"/>
	</xsl:call-template>
      </xsl:with-param>
      <xsl:with-param name="quiet" select="$chunk.quietly"/>
    </xsl:call-template>
  </xsl:template>
  
</xsl:stylesheet>

