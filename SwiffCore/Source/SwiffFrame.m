/*
    SwiffFrame.m
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


#import "SwiffFrame.h"
#import "SwiffPlacedObject.h"
#import "SwiffScene.h"
#import "SwiffSoundDefinition.h"
#import "SwiffSoundStreamBlock.h"

@interface SwiffFrame (FriendMethods)
- (void) _updateLabel:(NSString *)label;
- (void) _updateScene:(SwiffScene *)scene indexInScene:(NSUInteger)index1InScene;
@end


@implementation SwiffFrame {
    NSArray *_placedObjectsWithNames;
}

- (id) _initWithSortedPlacedObjects: (NSArray *) placedObjects
                          withNames: (NSArray *) placedObjectsWithNames
                        soundEvents: (NSArray *) soundEvents
                        streamSound: (SwiffSoundDefinition *) streamSound
                        streamBlock: (SwiffSoundStreamBlock *) streamBlock
{
    if ((self = [super init])) {
        _placedObjects = placedObjects;
        _soundEvents   = soundEvents;
        _streamSound   = streamSound;
        _streamBlock   = streamBlock;

        _placedObjectsWithNames = placedObjectsWithNames;
    }
    
    return self;
}


- (void) clearWeakReferences
{
    _scene = nil;
}


- (NSString *) description
{
    return [NSString stringWithFormat:@"<%@: %p; %lu>", [self class], self, (long unsigned)[self index1InMovie]];
}


#pragma mark -
#pragma mark Friend Methods

- (void) _updateScene:(SwiffScene *)scene indexInScene:(NSUInteger)indexInScene
{
    _scene = scene;
    _indexInScene = indexInScene;
}


- (void) _updateLabel:(NSString *)label 
{
    _label = [label copy];
}


#pragma mark -
#pragma mark Public Methods

- (SwiffPlacedObject *) placedObjectWithName:(NSString *)name
{
    for (SwiffPlacedObject *object in _placedObjectsWithNames) {
        if ([[object name] isEqualToString:name]) {
            return object;
        }
    }

    return nil;
}


#pragma mark -
#pragma mark Accessors

- (NSUInteger) index1InScene
{
    return _indexInScene + 1;
}


- (NSUInteger) index1InMovie
{
    return [_scene index1InMovie] + _indexInScene;
}


- (NSUInteger) indexInMovie
{
    return [_scene indexInMovie] + _indexInScene;
}


- (NSArray *) placedObjectsWithNames
{
    return _placedObjectsWithNames;
}


@end
