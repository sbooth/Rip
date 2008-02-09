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
