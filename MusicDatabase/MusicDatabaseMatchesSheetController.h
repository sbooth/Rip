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

// ========================================
// Properties
@property (copy) NSArray * matches;

// ========================================
// The meat & potatoes
- (void) beginMusicDatabaseMatchesSheetForWindow:(NSWindow *)window modalDelegate:(id)modalDelegate didEndSelector:(SEL)didEndSelector contextInfo:(void *)contextInfo;

// ========================================
// Action methods
- (IBAction) ok:(id)sender;
- (IBAction) cancel:(id)sender;

// ========================================
// A KVC-compliant object holding the data retrieved
- (id) selectedMatch;

@end
