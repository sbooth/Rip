/*
 *  Copyright (C) 2008 Stephen F. Booth <me@sbooth.org>
 *  All Rights Reserved
 */

#import "MusicDatabaseMatchesSheetController.h"

@implementation MusicDatabaseMatchesSheetController

@synthesize matches = _matches;

- (id) init
{
	return [super initWithWindowNibName:@"MusicDatabaseMatchesSheet"];
}

- (void) beginMusicDatabaseMatchesSheetForWindow:(NSWindow *)window modalDelegate:(id)modalDelegate didEndSelector:(SEL)didEndSelector contextInfo:(void *)contextInfo
{
	NSParameterAssert(nil != window);
	
	[[NSApplication sharedApplication] beginSheet:self.window
								   modalForWindow:window
									modalDelegate:modalDelegate
								   didEndSelector:didEndSelector
									  contextInfo:contextInfo];
}

- (IBAction) ok:(id)sender
{

#pragma unused(sender)

	[[NSApplication sharedApplication] endSheet:self.window returnCode:NSOKButton];
}

- (IBAction) cancel:(id)sender
{

#pragma unused(sender)

	[[NSApplication sharedApplication] endSheet:self.window returnCode:NSCancelButton];
}

- (id) selectedMatch
{
	return _matchesArrayController.selection;
}

@end
