/*
 *  Copyright (C) 2008 Stephen F. Booth <me@sbooth.org>
 *  All Rights Reserved
 */

#import <Cocoa/Cocoa.h>

// ========================================
// This class accomodates a custom view loaded from an NSViewController instance
// ========================================
@interface EncoderSettingsSheetController : NSWindowController
{
	IBOutlet NSView *_settingsView;
	
	@private
	NSViewController *_settingsViewController;
}

// ========================================
// Properties
@property (assign) NSViewController *settingsViewController;

// ========================================
// Action Methods
- (IBAction) ok:(id)sender;
- (IBAction) cancel:(id)sender;

@end
