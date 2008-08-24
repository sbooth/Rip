/*
 *  Copyright (C) 2008 Stephen F. Booth <me@sbooth.org>
 *  All Rights Reserved
 */

#import <Cocoa/Cocoa.h>

@interface EncoderPreferencesViewController : NSViewController
{
	IBOutlet NSArrayController *_encoderArrayController;
}

// ========================================
// Action methods
- (IBAction) selectDefaultEncoder:(id)sender;
- (IBAction) editEncoderSettings:(id)sender;

@end
