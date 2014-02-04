/************
 * AppDelegate
 * Author: Ian Glen <ian@ianglen.me>
 ************/

#import "AppDelegate.h"

@implementation AppDelegate


- (void)applicationDidFinishLaunching:(NSNotification *)aNotification
{
    // Insert code here to initialize your application
}

- (IBAction)browseForSWFFile:(id)sender
{
    NSOpenPanel *fileDialog = [NSOpenPanel openPanel];
    [fileDialog setCanChooseFiles:([_convertFolderCheckbox state] == NSOnState) ? NO : YES];
    [fileDialog setCanChooseDirectories:([_convertFolderCheckbox state] == NSOnState) ? YES : NO];
    [fileDialog setResolvesAliases:NO];
    [fileDialog setAllowsMultipleSelection:NO];
    [fileDialog setAllowedFileTypes:@[@"swf"]];
    
    if([fileDialog runModal] == NSFileHandlingPanelOKButton)
    {
        [_swfFileTextfield setStringValue:[[fileDialog URL] path]];
    }
}

- (IBAction)checkConvertFolder:(id)sender
{
    if([_convertFolderCheckbox state] == NSOnState)
    {
        [_swfFileLabel setStringValue:@"Folder of SWFs:"];
    }
    else
    {
        [_swfFileLabel setStringValue:@"SWF File:"];
    }
}

- (void)alertOnError:(NSString *)error
{
    [_spinner stopAnimation:self];
    
    NSAlert *alert = [[NSAlert alloc] init];
    [alert setAlertStyle:NSCriticalAlertStyle];
    [alert setMessageText:error];
    [alert addButtonWithTitle:@"OK"];
    [alert runModal];
}

- (IBAction)convert:(id)sender
{
    // non-blocking convert operation on seperate thread
    NSBlockOperation *convertOperation = [NSBlockOperation blockOperationWithBlock:^(void)
    {
        // start the spinner
        [_spinner startAnimation:self];
        
        NSMutableArray *swfFiles = [[NSMutableArray alloc] init];
        NSFileManager *fileManager = [NSFileManager defaultManager];
        BOOL isDirectory;
        
        // check for path to swf file
        if([[_swfFileTextfield stringValue] isEqualToString:@""])
        {
            [self alertOnError:[NSString stringWithFormat:@"Please select a %@.", ([_convertFolderCheckbox state] == NSOnState) ? @"folder" : @"SWF file"]];
            return;
        }
        
        // make sure exists
        if(![fileManager fileExistsAtPath:[_swfFileTextfield stringValue] isDirectory:&isDirectory])
        {
            [self alertOnError:[NSString stringWithFormat:@"%@ doesn't exist.", [[_swfFileTextfield stringValue] lastPathComponent]]];
            return;
        }
        
        // populate swf files array
        if([_convertFolderCheckbox state] == NSOnState)
        {
            // make sure directory was selected
            if(!isDirectory)
            {
                [self alertOnError:[NSString stringWithFormat:@"%@ isn't a directory.", [[_swfFileTextfield stringValue] lastPathComponent]]];
                return;
            }
            
            // traverse directory
            NSDirectoryEnumerator *swfDirectoryEnumerator = [fileManager enumeratorAtPath:[_swfFileTextfield stringValue]];
            
            // filter out all files except swfs
            NSString *swfDirectoryFile;
            while((swfDirectoryFile = [swfDirectoryEnumerator nextObject]))
            {
                if([[swfDirectoryFile pathExtension] isEqualToString:@"swf"])
                {
                    [swfFiles addObject:[[_swfFileTextfield stringValue] stringByAppendingPathComponent:swfDirectoryFile]];
                }
            }
            
            // make sure directory had some swf files in it
            if([swfFiles count] == 0)
            {
                [self alertOnError:[NSString stringWithFormat:@"%@ doesn't contain any SWF files.", [[_swfFileTextfield stringValue] lastPathComponent]]];
                return;
            }
        }
        else
        {
            // make sure directory wasn't selected
            if(isDirectory)
            {
                [self alertOnError:[NSString stringWithFormat:@"%@ is a directory.", [[_swfFileTextfield stringValue] lastPathComponent]]];
                return;
            }
            
            // make sure individual file is an SWF file
            if(![[[_swfFileTextfield stringValue] pathExtension] isEqualToString:@"swf"])
            {
                [self alertOnError:[NSString stringWithFormat:@"%@ isn't an SWF file.", [[_swfFileTextfield stringValue] lastPathComponent]]];
                return;
            }
            
            // convert individual file
            [swfFiles addObject:[_swfFileTextfield stringValue]];
        }
        
        // convert files in swf files array
        for(NSString *swfFile in swfFiles)
        {
            // open swf and parse it
            NSData *swfFileData = [[NSData alloc] initWithContentsOfFile:swfFile];
            
            // check if swf file was successfully opened
            if(!swfFileData)
            {
                [self alertOnError:[NSString stringWithFormat:@"%@ could not be read.", [swfFile lastPathComponent]]];
                return;
            }
            
            // load swf data into SwiffCore
            SwiffMovie *swfMovie = [[SwiffMovie alloc] initWithData:swfFileData];
            SwiffRenderer *swfRenderer = [[SwiffRenderer alloc] initWithMovie:swfMovie];
            
            // make sure frame count is 1, multiframe swfs not supported
            if([[swfMovie frames] count] != 1)
            {
                [self alertOnError:[NSString stringWithFormat:@"%@ could not be converted. Multi-frame SWF files are not supported.", [swfFile lastPathComponent]]];
                return;
            }
            
            // loop through frames in order to handle multi-frame pdfs
            for(NSUInteger frameCount = 0; frameCount < [[swfMovie frames] count]; frameCount++)
            {
                // create pdf file path
                NSString *pdfPath = [NSString stringWithFormat:@"%@/%@%@%@", [swfFile stringByDeletingLastPathComponent], [[swfFile lastPathComponent] stringByDeletingPathExtension], ([[swfMovie frames] count] != 1) ? [NSString stringWithFormat:@"%@%lu", @"_", (unsigned long)frameCount] : @"", @".pdf"];
                
                // convert pdf file path to CFURL
                CFStringRef pdfPathCFString = CFStringCreateWithCString(NULL, [pdfPath UTF8String], kCFStringEncodingUTF8);
                CFURLRef pdfPathCFURL = CFURLCreateWithFileSystemPath(NULL, pdfPathCFString, kCFURLPOSIXPathStyle, 0);
                
                // create PDF drawing context
                CGContextRef pdfContext = CGPDFContextCreateWithURL(pdfPathCFURL, NULL, NULL);
                
                // create dictionary for page information
                CGRect pageRect = [swfMovie stageRect];
                CFMutableDictionaryRef pageDictionary = CFDictionaryCreateMutable(NULL, 0, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
                CFDataRef boxData = CFDataCreate(NULL, (const UInt8 *)&pageRect, sizeof (CGRect));
                CFDictionarySetValue(pageDictionary, kCGPDFContextMediaBox, boxData);
                
                // create a page in the PDF file
                CGPDFContextBeginPage(pdfContext, pageDictionary);
                
                // flip drawing context to proper page orientation
                CGContextSaveGState(pdfContext);
                CGContextTranslateCTM(pdfContext, 0, pageRect.size.height);
                CGContextScaleCTM(pdfContext, 1.0, -1.0);
                
                // render frame on pdf
                [swfRenderer renderPlacedObjects:[[swfMovie frames][frameCount] placedObjects] inContext:pdfContext];
                
                // end pdf page
                CGPDFContextEndPage(pdfContext);
                
                // close pdf
                CGContextRelease(pdfContext);

            }
            
        }
        
        // stop spinner
        [_spinner stopAnimation:self];
        
        // swf file(s) converted successfully
        NSAlert *swfCompletionAlert = [[NSAlert alloc] init];
        [swfCompletionAlert setAlertStyle:NSInformationalAlertStyle];
        [swfCompletionAlert setMessageText:[NSString stringWithFormat:@"%@ converted successfully.", ([swfFiles count] > 1) ? [NSString stringWithFormat:@"%lu SWF files were", [swfFiles count]] : [NSString stringWithFormat:@"%@ was", [swfFiles[0] lastPathComponent]]]];
        [swfCompletionAlert addButtonWithTitle:@"OK"];
        [swfCompletionAlert runModal];
        
        return;
    }];
    
    [convertOperation start];
}


@end
