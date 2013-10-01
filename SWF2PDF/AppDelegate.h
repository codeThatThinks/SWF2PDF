/************
 * AppDelegate
 * Author: Ian Glen <ian@ianglen.me>
 ************/

#import <Cocoa/Cocoa.h>

@interface AppDelegate : NSObject <NSApplicationDelegate>


#pragma mark - SWF Parsing

@property (strong, atomic) SwiffSparseArray *definitions;
@property (assign, atomic) SwiffColor backgroundColor;


#pragma mark - Main Window Outlets

@property (strong, nonatomic) IBOutlet NSWindow *window;
@property (strong, nonatomic) IBOutlet NSTextFieldCell *swfFileLabel;
@property (strong, nonatomic) IBOutlet NSTextField *swfFileTextfield;
@property (strong, nonatomic) IBOutlet NSProgressIndicator *spinner;
@property (strong, nonatomic) IBOutlet NSButton *convertFolderCheckbox;


#pragma mark - Main Window Actions

- (IBAction)browseForSWFFile:(id)sender;
- (IBAction)convert:(id)sender;
- (IBAction)checkConvertFolder:(id)sender;


@end
