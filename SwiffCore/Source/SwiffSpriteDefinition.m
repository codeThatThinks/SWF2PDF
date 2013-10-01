/*
    SwiffSprite.m
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

#import "SwiffSpriteDefinition.h"

#import "SwiffFrame.h"
#import "SwiffMovie.h"
#import "SwiffParser.h"
#import "SwiffPlacedObject.h"
#import "SwiffPlacedDynamicText.h"
#import "SwiffScene.h"
#import "SwiffSceneAndFrameLabelData.h"
#import "SwiffSparseArray.h"
#import "SwiffSoundDefinition.h"
#import "SwiffSoundEvent.h"
#import "SwiffSoundStreamBlock.h"
#import "SwiffFilter.h"
#import "SwiffUtils.h"

// Associated value for parser - SwiffSceneAndFrameLabelData 
static NSString * const SwiffSpriteDefinitionSceneAndFrameLabelDataKey = @"SwiffSpriteDefinitionSceneAndFrameLabelData";

// Associated value for parser - NSMutableArray of the current SwiffSoundEvent objects
static NSString * const SwiffSpriteDefinitionSoundEventsKey = @"SwiffSpriteDefinitionSoundEvents";

// Associated value for parser - SwiffSoundDefinition for current streaming sound
static NSString * const SwiffSpriteDefinitionStreamSoundDefinitionKey = @"SwiffSpriteDefinitionStreamSoundDefinition";

// Associated value for parser - SwiffSoundStreamBlock for current streaming sound
static NSString * const SwiffSpriteDefinitionStreamBlockKey = @"SwiffSpriteDefinitionStreamBlock";


@interface SwiffFrame ()
- (id) _initWithSortedPlacedObjects: (NSArray *) placedObjects
                          withNames: (NSArray *) placedObjectsWithNames
                        soundEvents: (NSArray *) soundEvents
                        streamSound: (SwiffSoundDefinition *) streamSound
                        streamBlock: (SwiffSoundStreamBlock *) streamBlock;
@end


@interface SwiffSpriteDefinition ()
@property (nonatomic, weak) SwiffMovie *movie;
@end


@implementation SwiffSpriteDefinition {
    NSDictionary     *_labelToFrameMap;
    SwiffFrame       *_lastFrame;
    NSDictionary     *_sceneNameToSceneMap;
    SwiffSparseArray *_placedObjects;
    NSMutableArray   *_frames;
}

@synthesize movie        = _movie,
            libraryID    = _libraryID,
            bounds       = _bounds,
            renderBounds = _renderBounds;


#pragma mark -
#pragma mark Lifecycle

- (id) init
{
    if ((self = [super init])) {
        _frames = [[NSMutableArray alloc] init];
        _placedObjects = [[SwiffSparseArray alloc] init];
    }
    
    return self;
}


- (id) initWithParser:(SwiffParser *)parser movie:(SwiffMovie *)movie
{
    if ((self = [self init])) {
        SwiffParserReadUInt16(parser, &_libraryID);

        UInt16 frameCount;
        SwiffParserReadUInt16(parser, &frameCount);

        _movie = movie;

        SwiffParser *subparser = SwiffParserCreate(SwiffParserGetCurrentBytePointer(parser), SwiffParserGetBytesRemainingInCurrentTag(parser));
        SwiffParserSetStringEncoding(subparser, SwiffParserGetStringEncoding(parser));

        SwiffLog(@"Sprite", @"DEFINESPRITE defines id %ld", (long)_libraryID);

        while (SwiffParserIsValid(subparser)) {
            SwiffParserAdvanceToNextTag(subparser);
            
            SwiffTag  tag     = SwiffParserGetCurrentTag(subparser);
            NSInteger version = SwiffParserGetCurrentTagVersion(subparser);

            if (tag == SwiffTagEnd) break;

            [self _parser:subparser didFindTag:tag version:version];
        }

        [self _parserDidEnd:subparser];

        SwiffParserFree(subparser);

        SwiffLog(@"Sprite", @"END");
    
        if (!SwiffParserIsValid(parser)) {
            return nil;
        }
    }
    
    return self;
}


- (void) clearWeakReferences
{
    _movie = nil;
}


#pragma mark -
#pragma mark Tag Handlers

- (void) _parserDidEnd:(SwiffParser *)parser
{
    SwiffSceneAndFrameLabelData *frameLabelData = SwiffParserGetAssociatedValue(parser, SwiffSpriteDefinitionSceneAndFrameLabelDataKey);

    if (frameLabelData) {
        [frameLabelData applyLabelsToFrames:_frames];
        _scenes = [frameLabelData scenesForFrames:_frames];

        [frameLabelData clearWeakReferences];

    } else {
        SwiffScene *scene = [[SwiffScene alloc] initWithMovie:nil name:nil indexInMovie:0 frames:_frames];
        _scenes = [[NSArray alloc] initWithObjects:scene, nil];
    }
}

- (void) _parser:(SwiffParser *)parser didFindPlaceObjectTag:(SwiffTag)tag version:(NSInteger)version
{
    NSString *name = nil;
    BOOL      hasClipActions = NO, hasClipDepth = NO, hasName = NO, hasRatio = NO, hasColorTransform = NO, hasMatrix = NO, hasLibraryID = NO, move = NO;
    BOOL      hasImage = NO, hasClassName = NO, hasCacheAsBitmap = NO, hasBlendMode = NO, hasFilterList = NO;
    UInt16    depth;
    UInt16    libraryID;
    UInt16    ratio;
    UInt16    clipDepth;

    CGAffineTransform matrix     = CGAffineTransformIdentity;
    SwiffBlendMode    blendMode  = SwiffBlendModeNormal;
    NSArray          *filterList = nil;
    NSString         *className  = nil;
    SwiffColorTransform colorTransform;

    if (version == 2 || version == 3) {
        UInt32 tmp;

        SwiffParserReadUBits(parser, 1, &tmp);  hasClipActions    = tmp;
        SwiffParserReadUBits(parser, 1, &tmp);  hasClipDepth      = tmp;
        SwiffParserReadUBits(parser, 1, &tmp);  hasName           = tmp;
        SwiffParserReadUBits(parser, 1, &tmp);  hasRatio          = tmp;
        SwiffParserReadUBits(parser, 1, &tmp);  hasColorTransform = tmp;
        SwiffParserReadUBits(parser, 1, &tmp);  hasMatrix         = tmp;
        SwiffParserReadUBits(parser, 1, &tmp);  hasLibraryID      = tmp;
        SwiffParserReadUBits(parser, 1, &tmp);  move              = tmp;

        if (version == 3) {
            SwiffParserReadUBits(parser, 3, &tmp);
            SwiffParserReadUBits(parser, 1, &tmp);  hasImage         = tmp;
            SwiffParserReadUBits(parser, 1, &tmp);  hasClassName     = tmp;
            SwiffParserReadUBits(parser, 1, &tmp);  hasCacheAsBitmap = tmp;
            SwiffParserReadUBits(parser, 1, &tmp);  hasBlendMode     = tmp;
            SwiffParserReadUBits(parser, 1, &tmp);  hasFilterList    = tmp;

        } else {
            hasImage         = NO;
            hasClassName     = NO;
            hasCacheAsBitmap = NO;
            hasBlendMode     = NO;
            hasFilterList    = NO;
        }

        SwiffParserReadUInt16(parser, &depth);

        if (hasClassName || (hasImage && hasLibraryID)) {
            SwiffParserReadString(parser, &className);
        }

        if (hasLibraryID)       SwiffParserReadUInt16(parser, &libraryID);
        if (hasMatrix)          SwiffParserReadMatrix(parser, &matrix);
        if (hasColorTransform)  SwiffParserReadColorTransformWithAlpha(parser, &colorTransform);
        if (hasRatio)           SwiffParserReadUInt16(parser, &ratio);
        if (hasName)            SwiffParserReadString(parser, &name);
        if (hasClipDepth)       SwiffParserReadUInt16(parser, &clipDepth);

        if (hasFilterList) {
            filterList = [SwiffFilter filterListWithParser:parser];
        }
        
        if (hasBlendMode) {
            UInt8 tmp8;
            SwiffParserReadUInt8(parser, &tmp8);
            blendMode = tmp8;
        }
        
        if (hasCacheAsBitmap) {
            UInt8 rawCacheAsBitmap;
            SwiffParserReadUInt8(parser, &rawCacheAsBitmap);
            hasCacheAsBitmap = (rawCacheAsBitmap > 0);
        }

        if (hasClipActions) {
            //!issue4: Clip actions
        }

    } else {
        move         = YES;
        hasMatrix    = YES;
        hasLibraryID = YES;

        SwiffParserReadUInt16(parser, &libraryID);
        SwiffParserReadUInt16(parser, &depth);
        SwiffParserReadMatrix(parser, &matrix);

        SwiffParserByteAlign(parser);
        hasColorTransform = (SwiffParserGetBytesRemainingInCurrentTag(parser) > 0);

        if (hasColorTransform) {
            SwiffParserReadColorTransform(parser, &colorTransform);
        }
    }

    SwiffPlacedObject *existingPlacedObject = SwiffSparseArrayGetObjectAtIndex(_placedObjects, depth);
    SwiffPlacedObject *placedObject = SwiffPlacedObjectCreate(_movie, hasLibraryID ? libraryID : 0, move ? existingPlacedObject : nil);

    [placedObject setDepth:depth];

    if (hasImage) {
        [placedObject setPlacesImage:YES];
        [placedObject setClassName:className];
    }

    if (hasClassName)      [placedObject setClassName:className];
    if (hasClipDepth)      [placedObject setClipDepth:clipDepth];
    if (hasName)           [placedObject setName:name];
    if (hasRatio)          [placedObject setRatio:ratio];
    if (hasColorTransform) [placedObject setColorTransform:colorTransform];
    if (hasBlendMode)      [placedObject setBlendMode:blendMode];
    if (hasFilterList)     [placedObject setFilters:filterList];
    if (hasCacheAsBitmap)  [placedObject setCachesAsBitmap:YES];

    if (hasMatrix) {
        [placedObject setAffineTransform:matrix];
    }

    if (SwiffLogIsCategoryEnabled(@"Sprite")) {
        if (move) {
            SwiffLog(@"Sprite", @"PLACEOBJECT%ld moves object at depth %ld", (long)version, (long)depth);
        } else {
            SwiffLog(@"Sprite", @"PLACEOBJECT%ld places object %ld at depth %ld", (long)version, (long)[placedObject libraryID], (long)depth);
        }
    }

    SwiffSparseArraySetObjectAtIndex(_placedObjects, depth, placedObject);

    _lastFrame = nil;
}


- (void) _parser:(SwiffParser *)parser didFindRemoveObjectTag:(SwiffTag)tag version:(NSInteger)version
{
    UInt16 characterID = 0;
    UInt16 depth       = 0;

    if (version == 1) {
        SwiffParserReadUInt16(parser, &characterID);
    }

    SwiffParserReadUInt16(parser, &depth);

    if (SwiffLogIsCategoryEnabled(@"Sprite")) {
        if (version == 1) {
            SwiffLog(@"Sprite", @"REMOVEOBJECT removes object %d from depth %d", characterID, depth);
        } else {
            SwiffLog(@"Sprite", @"REMOVEOBJECT2 removes object from depth %d", depth);
        }
    }

    SwiffSparseArraySetObjectAtIndex(_placedObjects, depth, nil);
    _lastFrame = nil;
}


- (void) _parser:(SwiffParser *)parser didFindShowFrameTag:(SwiffTag)tag version:(NSInteger)version
{
    NSArray *placedObjects = nil;
    NSArray *placedObjectsWithNames = nil;

    // If _lastFrame is still valid, there were no modifications to it, use the same placed objects array
    //
    if (_lastFrame) {
        placedObjects = [_lastFrame placedObjects];
        placedObjectsWithNames = [_lastFrame placedObjectsWithNames];

    } else {
        NSMutableArray *sortedPlacedObjects = [[NSMutableArray alloc] init];
        NSMutableArray *sortedPlacedObjectsWithNames = [[NSMutableArray alloc] init];         
        
        for (SwiffPlacedObject *po in _placedObjects) {
            [sortedPlacedObjects addObject:po];
            if ([po name]) [sortedPlacedObjectsWithNames addObject:po];
        };

        if ([sortedPlacedObjects count]) {
            placedObjects          = sortedPlacedObjects;
            placedObjectsWithNames = sortedPlacedObjectsWithNames;
        } else {
        }
    }

    NSArray               *soundEvents = SwiffParserGetAssociatedValue(parser, SwiffSpriteDefinitionSoundEventsKey);
    SwiffSoundDefinition  *streamSound = SwiffParserGetAssociatedValue(parser, SwiffSpriteDefinitionStreamSoundDefinitionKey);
    SwiffSoundStreamBlock *streamBlock = SwiffParserGetAssociatedValue(parser, SwiffSpriteDefinitionStreamBlockKey);

    if (streamSound && !streamBlock) {
        streamSound = nil;
    }

    SwiffFrame *frame = [[SwiffFrame alloc] _initWithSortedPlacedObjects: placedObjects
                                                               withNames: placedObjectsWithNames
                                                             soundEvents: soundEvents
                                                             streamSound: streamSound
                                                             streamBlock: streamBlock];

    [_frames addObject:frame];
    _lastFrame = frame;


    SwiffLog(@"Sprite", @"SHOWFRAME");
}


- (void) _parser:(SwiffParser *)parser didFindFrameLabelTag:(SwiffTag)tag version:(NSInteger)version
{
    NSString *label = nil;
    SwiffParserReadString(parser, &label);

//    [_workingFrame setLabel:label];
}


- (void) _parser:(SwiffParser *)parser didFindTag:(SwiffTag)tag version:(NSInteger)version
{
    if (tag == SwiffTagDefineSceneAndFrameLabelData) {
        SwiffSceneAndFrameLabelData *existingData = SwiffParserGetAssociatedValue(parser, SwiffSpriteDefinitionSceneAndFrameLabelDataKey);
        [existingData clearWeakReferences];
        
        SwiffSceneAndFrameLabelData *data = [[SwiffSceneAndFrameLabelData alloc] initWithParser:parser movie:_movie];
        SwiffParserSetAssociatedValue(parser, SwiffSpriteDefinitionSceneAndFrameLabelDataKey, data);

    } else if (tag == SwiffTagPlaceObject) {
        [self _parser:parser didFindPlaceObjectTag:tag version:version];
            
    } else if (tag == SwiffTagRemoveObject) {
        [self _parser:parser didFindRemoveObjectTag:tag version:version];

    } else if (tag == SwiffTagShowFrame) {
        [self _parser:parser didFindShowFrameTag:tag version:version];

        // Reset sound events and stream block
        SwiffParserSetAssociatedValue(parser, SwiffSpriteDefinitionSoundEventsKey, nil);
        SwiffParserSetAssociatedValue(parser, SwiffSpriteDefinitionStreamBlockKey, nil);

    } else if (tag == SwiffTagFrameLabel) {
        [self _parser:parser didFindFrameLabelTag:tag version:version];

    } else if (tag == SwiffTagSoundStreamHead) {
        SwiffSoundDefinition *definition = [[SwiffSoundDefinition alloc] initWithParser:parser movie:_movie];
        SwiffParserSetAssociatedValue(parser, SwiffSpriteDefinitionStreamSoundDefinitionKey, definition);

    } else if (tag == SwiffTagSoundStreamBlock) {
        SwiffSoundDefinition *definition = SwiffParserGetAssociatedValue(parser, SwiffSpriteDefinitionStreamSoundDefinitionKey);
        
        SwiffSoundStreamBlock *block = [definition readSoundStreamBlockTagFromParser:parser];
        SwiffParserSetAssociatedValue(parser, SwiffSpriteDefinitionStreamBlockKey, block);

    } else if (tag == SwiffTagStartSound) {
        SwiffSoundEvent *event = [[SwiffSoundEvent alloc] initWithParser:parser];
    
        SwiffSoundDefinition *definition = [_movie soundDefinitionWithLibraryID:[event libraryID]];
        
        if (definition) {
            [event setDefinition:definition];
            
            NSMutableArray *events = SwiffParserGetAssociatedValue(parser, SwiffSpriteDefinitionSoundEventsKey);
            if (!events) {
                events = [[NSMutableArray alloc] init];

                SwiffParserSetAssociatedValue(parser, SwiffSpriteDefinitionSoundEventsKey, events);
                [events addObject:event];

            } else {
                [events addObject:event];
            }
        }
    }
}


#pragma mark -
#pragma mark Public Methods

- (SwiffFrame *) frameWithLabel:(NSString *)label
{
    if (!_labelToFrameMap) {
        NSMutableDictionary *map = [[NSMutableDictionary alloc] init];

        for (SwiffFrame *frame in _frames) {
            NSString *frameLabel = [frame label];
            if (frameLabel) [map setObject:frame forKey:frameLabel];
        }
        
        _labelToFrameMap = map;
    }

    return [_labelToFrameMap objectForKey:label];
}


- (SwiffFrame *) frameAtIndex1:(NSUInteger)index1
{
    if (index1 > 0 && index1 <= [_frames count]) {
        return [_frames objectAtIndex:(index1 - 1)];
    }
    
    return nil;
}


- (NSUInteger) index1OfFrame:(SwiffFrame *)frame
{
    NSUInteger index = [_frames indexOfObject:frame];
    return (index == NSNotFound) ? NSNotFound : (index + 1);
}


- (SwiffFrame *) frameAtIndex:(NSUInteger)index
{
    if (index < [_frames count]) {
        return [_frames objectAtIndex:index];
    }
    
    return nil;
}


- (NSUInteger) indexOfFrame:(SwiffFrame *)frame
{
    return [_frames indexOfObject:frame];
}


- (SwiffScene *) sceneWithName:(NSString *)name
{
    if (!_sceneNameToSceneMap) {
        NSMutableDictionary *map = [[NSMutableDictionary alloc] initWithCapacity:[_scenes count]];
        
        for (SwiffScene *scene in _scenes) {
            [map setObject:scene forKey:[scene name]];
        }
    
        _sceneNameToSceneMap = map;
    }

    return [_sceneNameToSceneMap objectForKey:name];
}


#pragma mark -
#pragma mark Accessors

- (void) _makeBounds
{
    for (SwiffFrame *frame in _frames) {
        for (SwiffPlacedObject *placedObject in [frame placedObjects]) {
            id<SwiffDefinition> definition = SwiffMovieGetDefinition(_movie, placedObject->_libraryID);
            
            CGRect bounds       = CGRectApplyAffineTransform([definition bounds],       placedObject->_affineTransform);
            CGRect renderBounds = CGRectApplyAffineTransform([definition renderBounds], placedObject->_affineTransform);
            
            if (CGRectIsEmpty(_bounds)) {
                _bounds = bounds;
            } else {
                _bounds = CGRectUnion(_bounds, bounds);
            }

            if (CGRectIsEmpty(_renderBounds)) {
                _renderBounds = renderBounds;
            } else {
                _renderBounds = CGRectUnion(_renderBounds, renderBounds);
            }
        }
    }
}


- (CGRect) renderBounds
{
    if (CGRectIsEmpty(_renderBounds)) {
        [self _makeBounds];
    }

    return _renderBounds;
}


- (CGRect) bounds
{
    if (CGRectIsEmpty(_bounds)) {
        [self _makeBounds];
    }
    
    return _bounds;
}

@end
