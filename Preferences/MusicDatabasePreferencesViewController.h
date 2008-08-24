/*
 *  Copyright (C) 2008 Stephen F. Booth <me@sbooth.org>
 *  All Rights Reserved
 */

#import <Cocoa/Cocoa.h>

@interface MusicDatabasePreferencesViewController : NSViewController
{
	IBOutlet NSArrayController *_musicDatabaseArrayController;
}

// ========================================
// Action methods
- (IBAction) selectDefaultMusicDatabase:(id)sender;
- (IBAction) editMusicDatabaseSettings:(id)sender;

@end
