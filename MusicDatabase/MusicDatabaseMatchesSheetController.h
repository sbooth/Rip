/*
 *  Copyright (C) 2008 Stephen F. Booth <me@sbooth.org>
 *  All Rights Reserved
 */

#import <Cocoa/Cocoa.h>

@interface MusicDatabaseMatchesSheetController : NSWindowController
{
	IBOutlet NSArrayController *_matchesArrayController;

@private
	NSArray *_matches;
}

@property (assign) NSArray * matches;

- (IBAction) ok:(id)sender;
- (IBAction) cancel:(id)sender;

- (id) selectedMatch;

@end
