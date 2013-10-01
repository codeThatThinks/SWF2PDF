/*
    SwiffHTMLToCoreTextConverter.m
    Copyright (c) 2011-2012, musictheory.net, LLC.  All rights reserved.

    Redistribution and use in source and binary forms, with or without
    modification, are permitted provided that the following conditions are met:
        * Redistributions of source code must retain the above copyright
          notice, this list of conditions and the following disclaimer.
        * Redistributions in binary form must reproduce the above copyright
          notice, this list of conditions and the following disclaimer in the
          documentation and/or other materials provided with the distribution.
        * Neither the name of musictheory.net, LLC nor the names of its contributors
          may be used to endorse or promote products derived from this software
          without specific prior written permission.

    THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
    ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
    WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
    DISCLAIMED. IN NO EVENT SHALL MUSICTHEORY.NET, LLC BE LIABLE FOR ANY
    DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
    (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
    LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
    ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
    (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
    SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
*/

#import "SwiffHTMLToCoreTextConverter.h"

#import <SwiffUtils.h>
#import <SwiffDynamicTextAttributes.h>

#include <libxml/HTMLparser.h>

typedef NS_ENUM(NSInteger, SwiffHTMLToCoreTextConverterTag) {
    SwiffHTMLToCoreTextConverterTag_Unknown = 0,

    SwiffHTMLToCoreTextConverterTag_A,
    SwiffHTMLToCoreTextConverterTag_B,
    SwiffHTMLToCoreTextConverterTag_I,
    SwiffHTMLToCoreTextConverterTag_P,
    SwiffHTMLToCoreTextConverterTag_U,
    SwiffHTMLToCoreTextConverterTag_BR,
    SwiffHTMLToCoreTextConverterTag_LI,
    SwiffHTMLToCoreTextConverterTag_TAB,
    SwiffHTMLToCoreTextConverterTag_FONT,
    SwiffHTMLToCoreTextConverterTag_TEXTFORMAT
};


@implementation SwiffHTMLToCoreTextConverter {
    SwiffDynamicTextAttributes *_attributes;

    NSMutableString *_characters;
    NSInteger        _boldCount;
    NSInteger        _italicCount;
    NSInteger        _underlineCount;
    BOOL             _needsParagraphBreak;

    NSMutableAttributedString *_output;
}


+ (id) sharedInstance
{
    static id sharedInstance = nil;

    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedInstance = [[self alloc] init];
    });

    return sharedInstance;
}


#pragma mark -
#pragma mark Parsing

- (void) _flush
{
    if ([_characters length]) {
        [_attributes setBold:      (_boldCount      > 0)];
        [_attributes setItalic:    (_italicCount    > 0)];
        [_attributes setUnderline: (_underlineCount > 0)];

        NSDictionary *coreTextAttributes = [_attributes copyCoreTextAttributes];
       
        NSAttributedString *toAppend = [[NSAttributedString alloc] initWithString:_characters attributes:coreTextAttributes];
        [_output appendAttributedString:toAppend];
        
        _characters = [[NSMutableString alloc] init];
    }
}


- (void) _cloneAttributes
{
    _attributes = [_attributes copy];
}


static SwiffHTMLToCoreTextConverterTag sGetTagForString(const xmlChar *inString)
{
    const char  c = toupper(inString[0]);
    const char *s = (const char *)inString;
    size_t length = strlen(s);

    if (     (c == 'A') && (0 == strncasecmp("A",          s, length)))  return SwiffHTMLToCoreTextConverterTag_A;
    else if ((c == 'B') && (0 == strncasecmp("B",          s, length)))  return SwiffHTMLToCoreTextConverterTag_B;
    else if ((c == 'B') && (0 == strncasecmp("BR",         s, length)))  return SwiffHTMLToCoreTextConverterTag_BR;
    else if ((c == 'F') && (0 == strncasecmp("FONT",       s, length)))  return SwiffHTMLToCoreTextConverterTag_FONT;
    else if ((c == 'I') && (0 == strncasecmp("I",          s, length)))  return SwiffHTMLToCoreTextConverterTag_I;
    else if ((c == 'L') && (0 == strncasecmp("LI",         s, length)))  return SwiffHTMLToCoreTextConverterTag_LI;
    else if ((c == 'P') && (0 == strncasecmp("P",          s, length)))  return SwiffHTMLToCoreTextConverterTag_P;
    else if ((c == 'T') && (0 == strncasecmp("TAB",        s, length)))  return SwiffHTMLToCoreTextConverterTag_TAB;
    else if ((c == 'T') && (0 == strncasecmp("TEXTFORMAT", s, length)))  return SwiffHTMLToCoreTextConverterTag_TEXTFORMAT;
    else if ((c == 'U') && (0 == strncasecmp("U",          s, length)))  return SwiffHTMLToCoreTextConverterTag_U;
    
    return SwiffHTMLToCoreTextConverterTag_Unknown;
}


static void sStartFontElement(SwiffHTMLToCoreTextConverter *self, xmlElementPtr element)
{
    SwiffDynamicTextAttributes *attributes = self->_attributes;

    // Handle "face" attribute
    {
        char *faceCString = (char *)xmlGetProp((xmlNodePtr)element, (xmlChar *)"face");

        if (faceCString) {
            NSString *fontName = [[NSString alloc] initWithBytesNoCopy:faceCString length:strlen(faceCString) encoding:NSUTF8StringEncoding freeWhenDone:YES];
            [attributes setFontName:fontName];
        }
    }

    // Handle "size" attribute
    {
        char *sizeCString  = (char *)xmlGetProp((xmlNodePtr)element, (xmlChar *)"size");

        if (sizeCString) {
            char c0 = sizeCString[0];
            
            //!spec: "size, which is specified in twips, and may include a leading
            //        '+' or '-' for relative sizes" (page 196)
            //
            // In reality, the font size is specified in points
            //
            SwiffTwips fontSize = [attributes fontSize];
            
            if (c0 == '+') {
                fontSize += atoi(&sizeCString[1]);
            } else if (c0 == '-') {
                fontSize -= atoi(&sizeCString[1]);
            } else {
                fontSize  = atoi(sizeCString);
            }
            
            [attributes setFontSize:fontSize];
            
            free(sizeCString);
        }
    }

    // Handle "color" attribute
    {
        char *colorCString = (char *)xmlGetProp((xmlNodePtr)element, (xmlChar *)"color");

        if (colorCString) {
            if (colorCString[0] == '#') {
                unsigned long hex = strtoul(&colorCString[1], NULL, 16);

                SwiffColor color;
                color.red   = ((hex & 0xFF0000) >> 16) / 255.0;
                color.green = ((hex & 0x00FF00) >>  8) / 255.0;
                color.blue  =  (hex & 0x0000FF)        / 255.0;
                color.alpha = 1.0;
                
                [attributes setFontColor:&color];
            }

            free(colorCString);
        }
    }
    
    //!spec: Handle undocumented "letterSpacing" attribute
    {
        char *spacingCString = (char *)xmlGetProp((xmlNodePtr)element, (xmlChar *)"letterSpacing");

        if (spacingCString) {
            free(spacingCString);
        }
    }
    
}


static void sStartParagraphElement(SwiffHTMLToCoreTextConverter *self, xmlElementPtr element)
{
    SwiffDynamicTextAttributes *attributes = self->_attributes;

    char *alignCString  = (char *)xmlGetProp((xmlNodePtr)element, (xmlChar *)"align");

    if (alignCString) {
        if (0 == strcasecmp(alignCString, "left")) {
            [attributes setTextAlignment:kCTLeftTextAlignment];
        } else if (0 == strcasecmp(alignCString, "center")) {
            [attributes setTextAlignment:kCTCenterTextAlignment];
        } else if (0 == strcasecmp(alignCString, "right")) {
            [attributes setTextAlignment:kCTRightTextAlignment];
        }
        
        free(alignCString);
    }
}


static void sStartTextFormatElement(SwiffHTMLToCoreTextConverter *self, xmlElementPtr element)
{
    SwiffDynamicTextAttributes *attributes = self->_attributes;

    char *leftMarginCString  = (char *)xmlGetProp((xmlNodePtr)element, (xmlChar *)"leftmargin");
    char *rightMarginCString = (char *)xmlGetProp((xmlNodePtr)element, (xmlChar *)"rightmargin");
    char *indentCString      = (char *)xmlGetProp((xmlNodePtr)element, (xmlChar *)"indent");
    char *leadingCString     = (char *)xmlGetProp((xmlNodePtr)element, (xmlChar *)"leading");
    char *blockIndentCString = (char *)xmlGetProp((xmlNodePtr)element, (xmlChar *)"blockindent");
    char *tabStopsCString    = (char *)xmlGetProp((xmlNodePtr)element, (xmlChar *)"tabstops");

    if (leftMarginCString) {
        [attributes setLeftMarginInTwips:atoi(leftMarginCString)];
    }

    if (rightMarginCString) {
        [attributes setRightMarginInTwips:atoi(rightMarginCString)];
    }

    if (indentCString) {
        [attributes setIndentInTwips:atoi(indentCString)];
    }

    if (leadingCString) {
        [attributes setLeadingInTwips:atoi(leadingCString)];
    }

    if (tabStopsCString) {
        NSString *tabStops = [[NSString alloc] initWithBytesNoCopy:tabStopsCString length:strlen(tabStopsCString) encoding:NSUTF8StringEncoding freeWhenDone:YES];
        [attributes setTabStopsString:tabStops];
        tabStopsCString = NULL;
    }

    // What is the difference between block indent and left margin?
    if (blockIndentCString) {
        SwiffTwips twips = [attributes leftMarginInTwips];
        twips += atoi(leftMarginCString); 
        [attributes setLeftMarginInTwips:twips];
    }

    free(leftMarginCString);
    free(rightMarginCString);
    free(indentCString);
    free(leadingCString);
    free(blockIndentCString);
    free(tabStopsCString);
}


static void sStartElement(SwiffHTMLToCoreTextConverter *self, xmlElementPtr element, SwiffHTMLToCoreTextConverterTag tag)
{
    if (tag == SwiffHTMLToCoreTextConverterTag_A) {
        //!issue5: Dynamic Text HTML <a> support

    } else if (tag == SwiffHTMLToCoreTextConverterTag_B) {
        [self _flush];  self->_boldCount++;

    } else if (tag == SwiffHTMLToCoreTextConverterTag_BR) {
        [self->_characters appendString:@"\n"];

    } else if (tag == SwiffHTMLToCoreTextConverterTag_FONT) {
        [self _flush];
        [self _cloneAttributes];
        sStartFontElement(self, element);

    } else if (tag == SwiffHTMLToCoreTextConverterTag_I) {
        [self _flush];  self->_italicCount++;

    } else if (tag == SwiffHTMLToCoreTextConverterTag_LI) {
        [self->_characters appendFormat:@"%C ", (unsigned short)0x2022];

    } else if (tag == SwiffHTMLToCoreTextConverterTag_P) {
        if (self->_needsParagraphBreak) {
            [self->_characters appendString:@"\n"];
            self->_needsParagraphBreak = NO;
        }

        [self _flush];
        [self _cloneAttributes];
        sStartParagraphElement(self, element);

    } else if (tag == SwiffHTMLToCoreTextConverterTag_TAB) {
        [self->_characters appendString:@"\t"];

    } else if (tag == SwiffHTMLToCoreTextConverterTag_TEXTFORMAT) {
        [self _flush];
        [self _cloneAttributes];
        sStartTextFormatElement(self, element);

    } else if (tag == SwiffHTMLToCoreTextConverterTag_U) {
        [self _flush];  self->_underlineCount++;
    }
}


static void sEndElement(SwiffHTMLToCoreTextConverter *self, xmlElementPtr element, SwiffHTMLToCoreTextConverterTag tag)
{
    if (tag == SwiffHTMLToCoreTextConverterTag_A) {
        //!issue5: Dynamic Text HTML <a> support

    } else if (tag == SwiffHTMLToCoreTextConverterTag_B) {
        self->_boldCount--;  [self _flush];

    } else if (tag == SwiffHTMLToCoreTextConverterTag_FONT) {
        [self _flush];

    } else if (tag == SwiffHTMLToCoreTextConverterTag_I) {
        self->_italicCount--;  [self _flush];

    } else if (tag == SwiffHTMLToCoreTextConverterTag_LI) {
        [self->_characters appendString:@"\n"];

    } else if (tag == SwiffHTMLToCoreTextConverterTag_P) {
        self->_needsParagraphBreak = YES;
        [self _flush];

    } else if (tag == SwiffHTMLToCoreTextConverterTag_TEXTFORMAT) {
        [self _flush];

    } else if (tag == SwiffHTMLToCoreTextConverterTag_U) {
        self->_underlineCount--;  [self _flush];
    }
}


static void sParseNode(SwiffHTMLToCoreTextConverter *self, xmlNodePtr node)
{
    SwiffDynamicTextAttributes *savedAttributes = self->_attributes;
    
    xmlElementType type    = node->type;
    xmlElementPtr  element = (type == XML_ELEMENT_NODE) ? (xmlElementPtr)node : NULL;
    SwiffHTMLToCoreTextConverterTag tag = element ? sGetTagForString(element->name) : SwiffHTMLToCoreTextConverterTag_Unknown;

    if (tag != SwiffHTMLToCoreTextConverterTag_Unknown) {
        sStartElement(self, element, tag);
    }

    xmlNodePtr childNode = node->children;
    while (childNode) {
        sParseNode(self, childNode);
        childNode = childNode->next;
    }
    
    if (type == XML_TEXT_NODE) {
        xmlChar *content = xmlNodeGetContent(node);

        if (content) {
            size_t length = strlen((const char *)content);

            NSString *string = [[NSString alloc] initWithBytesNoCopy:(void *)content length:length encoding:NSUTF8StringEncoding freeWhenDone:YES];
            [self->_characters appendString:string];
        }
    }

    if (tag != SwiffHTMLToCoreTextConverterTag_Unknown) {
        sEndElement(self, element, tag);
    }

    // Restore parser state from stack
    self->_attributes = savedAttributes;
}


- (NSAttributedString *) copyAttributedStringForHTML:(NSString *)string baseAttributes:(SwiffDynamicTextAttributes *)baseAttributes
{
    if (!string) return NULL;

    CFStringRef cfString = (__bridge CFStringRef)string;
    CFIndex     length   = 0;
    CFRange     range    = CFRangeMake(0, CFStringGetLength(cfString));

    CFStringGetBytes((__bridge CFStringRef)string, range, kCFStringEncodingUTF8, 0, 0, NULL, 0, &length);

    UInt8 *buffer = (UInt8 *)malloc(length);
    CFStringGetBytes(cfString, range, kCFStringEncodingUTF8, 0, 0, buffer, length, &length);
    
    htmlDocPtr htmlDoc = htmlReadMemory((const char *)buffer, length, NULL, "UTF-8", 0);
   
    _characters     = [[NSMutableString alloc] init];
    _output         = [[NSMutableAttributedString alloc] init];
    _attributes     = baseAttributes;
    _boldCount      = [baseAttributes isBold]      ? 1 : 0;
    _italicCount    = [baseAttributes isItalic]    ? 1 : 0;
    _underlineCount = [baseAttributes isUnderline] ? 1 : 0;
    _needsParagraphBreak = NO;

    if (!_attributes) {
        _attributes = [[SwiffDynamicTextAttributes alloc] init];
    }

    if (htmlDoc) {
        sParseNode(self, (xmlNodePtr)htmlDoc);
        xmlFreeDoc(htmlDoc);

        [self _flush];
    }

    NSAttributedString *output = _output;
    _output = NULL;

    _attributes = nil;
    _characters = nil;
    
    free(buffer);
    
    return output;
}

@end
