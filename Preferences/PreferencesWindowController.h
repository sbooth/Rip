/*
 *  Copyright (C) 2008 Stephen F. Booth <me@sbooth.org>
 *  All Rights Reserved
 */

#import <Cocoa/Cocoa.h>

@class EncoderManager;

@interface PreferencesWindowController : NSWindowController
{
	IBOutlet NSArrayController *_arrayController;
	@private
	EncoderManager *_em;
}

- (IBAction) addEncoder:(id)sender;

@end
