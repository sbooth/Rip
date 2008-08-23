/*
 *  Copyright (C) 2008 Stephen F. Booth <me@sbooth.org>
 *  All Rights Reserved
 */

#import <Cocoa/Cocoa.h>

@class MusicDatabaseQueryOperation;

// ========================================
// The interface a music database (FreeDB, MusicBrainz, etc) must implement to integrate with Rip
// ========================================
@protocol MusicDatabaseInterface

// The default database settings, if any
- (NSDictionary *) defaultSettings;

// Create an instance of NSViewController allowing users to edit the database's configuration
// The controller's representedObject will be set to the applicable database settings (NSDictionary *)
- (NSViewController *) configurationViewController;

// Provide an instance of an MusicDatabaseQueryOperation subclass
- (MusicDatabaseQueryOperation *) musicDatabaseQueryOperation;

@end
