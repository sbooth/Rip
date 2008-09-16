/*
 *  Copyright (C) 2008 Stephen F. Booth <me@sbooth.org>
 *  All Rights Reserved
 */

#import <Cocoa/Cocoa.h>

@interface MusicDatabasePreferencesViewController : NSViewController
{
	IBOutlet NSArrayController *_musicDatabaseArrayController;
	IBOutlet NSView *_musicDatabaseSettingsView;
	
@private
	NSViewController *_musicDatabaseSettingsViewController;
}

@property (readonly, assign) NSArray * availableMusicDatabases;

// ========================================
// Action methods
- (IBAction) selectDefaultMusicDatabase:(id)sender;

@end
