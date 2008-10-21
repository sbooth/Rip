/*
 *  Copyright (C) 2008 Stephen F. Booth <me@sbooth.org>
 *  All Rights Reserved
 */

#import <Cocoa/Cocoa.h>

@interface EncoderWindowController : NSWindowController
{
	IBOutlet NSArrayController *_arrayController;
}

- (IBAction) toggleEncoderWindow:(id)sender;

@end
