/*
 *  Copyright (C) 2008 Stephen F. Booth <me@sbooth.org>
 *  All Rights Reserved
 */

#import <Cocoa/Cocoa.h>

// ========================================
// KVC key names for the encoder dictionaries
// ========================================
extern NSString * const		kMusicDatabaseBundleKey; // NSBundle *
extern NSString * const		kMusicDatabaseSettingsKey; // NSDictionary *

@interface MusicDatabaseManager : NSObject
{
}

// ========================================
// Returns an array of NSBundle * objects whose principalClasses implement the MusicDatabaseInterface protocol
@property (readonly) NSArray * availableMusicDatabases;

// ========================================
// Returns an NSBundle * object corresponding to the user's default music database
@property (assign) NSBundle * defaultMusicDatabase;

// ========================================
// The shared instance
+ (id) sharedMusicDatabaseManager;

- (NSDictionary *) settingsForMusicDatabase:(NSBundle *)musicDatabase;
- (void) storeSettings:(NSDictionary *)musicDatabaseSettings forMusicDatabase:(NSBundle *)musicDatabase;

@end
