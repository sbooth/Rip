/*
 *  Copyright (C) 2008 Stephen F. Booth <me@sbooth.org>
 *  All Rights Reserved
 */

#import <Cocoa/Cocoa.h>

@interface EncoderPreferencesViewController : NSViewController
{
	IBOutlet NSArrayController *_encoderArrayController;
	IBOutlet NSView *_encoderSettingsView;

@private
	NSViewController *_encoderSettingsViewController;
}

@property (readonly, assign) NSArray * availableEncoders;

// ========================================
// Action methods
- (IBAction) selectDefaultEncoder:(id)sender;

@end
