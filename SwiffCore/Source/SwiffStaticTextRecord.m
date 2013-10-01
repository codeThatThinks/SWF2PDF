/*
    SwiffStaticTextRecord.m
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

#import "SwiffStaticTextRecord.h"

#import "SwiffParser.h"
#import "SwiffUtils.h"

@implementation SwiffStaticTextRecord

+ (NSArray *) textRecordArrayWithParser:(SwiffParser *)parser glyphBits:(UInt8)glyphBits advanceBits:(UInt8)advanceBits
{
    NSMutableArray  *result = [NSMutableArray array];
    SwiffStaticTextRecord *record = nil;

    do {
        record = [[SwiffStaticTextRecord alloc] initWithParser:parser glyphBits:glyphBits advanceBits:advanceBits];
        if (record) [result addObject:record];
    } while (record);

    return result;
}


- (id) initWithParser:(SwiffParser *)parser glyphBits:(UInt8)glyphBits advanceBits:(UInt8)advanceBits
{
    if ((self = [super init])) {
        SwiffParserByteAlign(parser);
    
        UInt32 textRecordType, reserved, hasFont, hasColor, hasYOffset, hasXOffset;
        SwiffParserReadUBits(parser, 1, &textRecordType);
        SwiffParserReadUBits(parser, 3, &reserved);
        SwiffParserReadUBits(parser, 1, &hasFont);
        SwiffParserReadUBits(parser, 1, &hasColor);
        SwiffParserReadUBits(parser, 1, &hasYOffset);
        SwiffParserReadUBits(parser, 1, &hasXOffset);
        
        if (textRecordType == 1) {
            _hasFont  = hasFont;
            _hasColor = hasColor;
            
            if (hasFont) {
                UInt16 fontID;
                SwiffParserReadUInt16(parser, &fontID);
                _fontID = fontID;
            }

            if (hasColor) {
                if (SwiffParserGetCurrentTagVersion(parser) >= 2) {
                    SwiffParserReadColorRGBA(parser, &_color);
                } else {
                    SwiffParserReadColorRGB(parser, &_color);
                }
            }
            
            if (hasXOffset) {
                SInt16 x = 0;
                SwiffParserReadSInt16(parser, &x);
                _xOffset = SwiffGetCGFloatFromTwips(x);
                _hasXOffset = YES;
            }

            if (hasYOffset) {
                SInt16 y = 0;
                SwiffParserReadSInt16(parser, &y);
                _yOffset = SwiffGetCGFloatFromTwips(y);
                _hasYOffset = YES;
            }
            
            if (hasFont) {
                UInt16 height;
                SwiffParserReadUInt16(parser, &height);
                _textHeight = SwiffGetCGFloatFromTwips(height);
            }
            
            UInt8 glyphCount;
            SwiffParserReadUInt8(parser, &glyphCount);
            _glyphEntriesCount = glyphCount;
            _glyphEntries = calloc(glyphCount, sizeof(SwiffStaticTextRecordGlyphEntry));

            for (UInt8 i = 0; i < _glyphEntriesCount; i++) {
                UInt32 glyphIndex   = 0;
                SInt32 glyphAdvance = 0;

                SwiffParserReadUBits(parser, glyphBits,   &glyphIndex);
                SwiffParserReadSBits(parser, advanceBits, &glyphAdvance);
                
                _glyphEntries[i].index   = glyphIndex;
                _glyphEntries[i].advance = SwiffGetCGFloatFromTwips(glyphAdvance);
            }
            
        } else {
            return nil;
        }
        
        if (!SwiffParserIsValid(parser)) {
            return nil;
        }
    }
    
    return self;
}


- (void) dealloc
{
    free(_glyphEntries);
    _glyphEntries = NULL;
}


#pragma mark -
#pragma mark Accessors

- (SwiffColor *) colorPointer
{
    return &_color;
}


@end
