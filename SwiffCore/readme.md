# SwiffCore

SwiffCore is a Mac OS X and iOS framework that renders vector shapes and animations stored in the SWF format.  It also provides basic support for bitmaps, fonts, text, and MP3 streams.

It **isn't** a Flash runtime.  It doesn't enable you to run your interactive Flash games on iOS.  It will, however, accurately render your existing vector graphics and animations.

SwiffCore is open source and freely available via a [BSD-style license](https://github.com/musictheory/SwiffCore/blob/master/license).


## Why?

I needed a solution for [Theory Lessons](http://itunes.apple.com/us/app/theory-lessons/id493157418?ls=1&mt=8), the iOS version of my music theory lessons (http://www.musictheory.net/lessons).
Each lesson contains several hundred frames of vector graphics and accompanying music examples.  

During initial development, I explored several options:

1. **Use Adobe Flash Professional's export-to-iOS feature**  
This creates a standalone .ipa file of your entire Flash project.  I couldn't find a safe, supported way of accessing these from my app.  Also, I would rather not inject a blob of Adobe-quality binary code into my product.

2. **Generate PNG files for each frame, in various resolutions**  
I had already written a SWF->PNG converter for Mac OS X .  It used WebKit to load the Flash Player plug-in, seek to a specific frame, then capture the frame using the screenshot APIs).  While the resulting images were accurate, they also used a large amount of space on disk (~45MB).

3. **Generate a movie file for each lesson**  
While iOS supports both the H.264 and MPEG-4 formats, neither is well suited for text and simple vector graphic content.

4. **Use [as3swf](https://github.com/claus/as3swf)'s Shape Export to Objective-C to generate classes for each lesson.**  
This resulted in a very large binary size.

5. **Write my own shape exported into a proprietery data format, then render it**  
This is basically an abstraction layer on #4.  At some point, the data format begins to look like SWF.  Why create a new data format when I can just:

6. **Read the SWF file and render it myself.**


## Usage

Using the framework is fairly simple:

1. Create an NSData instance containing your SWF file
2. Load it into a SwiffMovie instance using `-[SwiffMovie initWithData:]`
3. Make an accompanying SwiffView instance using `-[SwiffView initWithFrame:movie:]`
4. Play it using the SwiffPlayhead returned by `-[SwiffView playhead]`


## Design

Under the hood, SwiffCore uses Core Graphics to draw the vector shapes and static text, Core Text to draw dynamic
text fields, and Core Audio to playback sounds and music.  It composites all graphics into a Core Animation CALayer,
contained in a UIView or NSView.  

Optionally, multiple CALayers can be used (via `-[SwiffPlacedObject setWantsLayer:YES]`) to reduce redrawing.
Placed objects promoted to layers also animate at a full 60fps (even when the source movie is less than 60fps).

For more information, read the [SwiffCore Overview wiki article](https://github.com/musictheory/SwiffCore/wiki/Overview).


## What's supported?
(outstanding issues in parentheses)

* Sprites / Movie Clips
* Shapes
  * Line styles ([#9](https://github.com/musictheory/SwiffCore/issues/9), [#10](https://github.com/musictheory/SwiffCore/issues/10))
  * Solid color fills
  * Gradient fills
  * Bitmap fills (all formats) ([#11](https://github.com/musictheory/SwiffCore/issues/11), [#12](https://github.com/musictheory/SwiffCore/issues/12), [#14](https://github.com/musictheory/SwiffCore/issues/14))
  * Mask layers
* Scenes and frame labels
* Animation / Tweens (both motion and classic)
* Text fields (both dynamic and static)
* Embedded fonts
* Color effects
* Event sounds (MP3 only)
* Stream sounds (MP3 only)
* Basic layer blend modes ([#7](https://github.com/musictheory/SwiffCore/issues/7))


## What's not supported?

* Any kind of scripting or interaction ([#2](https://github.com/musictheory/SwiffCore/issues/2), [#4](https://github.com/musictheory/SwiffCore/issues/4), [#5](https://github.com/musictheory/SwiffCore/issues/5))
* Filters ([#13](https://github.com/musictheory/SwiffCore/issues/13))
* Morph Shapes ([#1](https://github.com/musictheory/SwiffCore/issues/1))
* Video ([#3](https://github.com/musictheory/SwiffCore/issues/3))


## Performance

Ultimately, performance depends on the source movie.  If SwiffCore has to redraw several objects per frame, and those frames contain gradients and/or complex paths, it's easy to saturate the CPU and drop frames (even on A5 devices).  After a few migraine-inducing Instruments sessions, I am **very** grateful that Apple never allowed Flash on the original iPhone.

Redrawing is reduced when `SwiffPlacedObject.wantsLayer` is set to YES, but memory footprint increases.  Also, several moving CALayers can saturate the GPU.  Ultimately, you will want to keep some movie clips in the main content layer, while promoting frequently-moving ones to their own layers.

For [Theory Lessons](http://itunes.apple.com/us/app/theory-lessons/id493157418?ls=1&mt=8) on an iPhone 3GS, SwiffCore rendered all of my movies at a full 20fps (the original frame rate) without using wantsLayer.  I then promoted specific SwiffPlacedObject instances to have their own layer (wantsLayer=YES) to create fluid 60fps animations.

I did this by running [UpgradeToLayers.jsfl](https://github.com/musictheory/SwiffCore/blob/master/Examples/UpgradeToLayers.jsfl) on my source movies.  This assigns an instance name of `_layer_X` (X increments) to each movie clip involved in a motion tween.  At runtime, in the `-swiffView:willUpdateCurrentFrame:` delegate callback, I promote these placed objects to wantsLayer=YES:

    - (void) swiffView:(SwiffView *)swiffView willUpdateCurrentFrame:(SwiffFrame *)frame
    {
        for (SwiffPlacedObject *placedObject in [frame placedObjects]) {
            NSString *name = [placedObject name];
    
            if ([name hasPrefix:@"_layer"]) {
                [placedObject setWantsLayer:YES];
                [placedObject setLayerIdentifier:name];
            }
        }
    }

An alternate approach would be to promote movie clips that have "Cache as bitmap" checked:

    - (void) swiffView:(SwiffView *)swiffView willUpdateCurrentFrame:(SwiffFrame *)frame
    {
        for (SwiffPlacedObject *placedObject in [frame placedObjects]) {
            [placedObject setWantsLayer:[placedObject cachesAsBitmap]];
        }
    }

## Resources

Here are some resources that were helpful during SwiffCore development:

* [SWF File Format Specification (version 10, PDF)](http://wwwimages.adobe.com/www.adobe.com/content/dam/Adobe/en/devnet/swf/pdf/swf_file_format_spec_v10.pdf)
* [Converting Flash Shapes to WPF](http://blogs.msdn.com/b/mswanson/archive/2006/02/27/539749.aspx) - An article on SWF shape parsing
* [Hacking SWF ... Shapes](http://wahlers.com.br/claus/blog/hacking-swf-1-shapes-in-flash/) - Another article on SWF shape parsing
* [Adobe Flex SDK Source](http://opensource.adobe.com/svn/opensource/flex/sdk/) - Includes a .swf parsing implementation in Java
* [as3swf](https://github.com/claus/as3swf) - A .swf parsing implementation in ActionScript
* [gameswf](http://tulrich.com/textweb.pl?path=geekstuff/gameswf.txt) - An older public domain .swf parser in C++
