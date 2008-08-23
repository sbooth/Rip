/*
 *  Copyright (C) 2008 Stephen F. Booth <me@sbooth.org>
 *  All Rights Reserved
 */

#import "MusicDatabaseManager.h"
#import "PlugInManager.h"
#import "MusicDatabaseInterface/MusicDatabaseInterface.h"
#import "MusicDatabaseInterface/MusicDatabaseQueryOperation.h"

// ========================================
// KVC key names for the music database dictionaries
// ========================================
NSString * const	kMusicDatabaseBundleKey					= @"bundle";
NSString * const	kMusicDatabaseSettingsKey				= @"settings";

// ========================================
// Static variables
// ========================================
static MusicDatabaseManager *sSharedMusicDatabaseManager	= nil;

@implementation MusicDatabaseManager

+ (id) sharedMusicDatabaseManager
{
	if(!sSharedMusicDatabaseManager)
		sSharedMusicDatabaseManager = [[MusicDatabaseManager alloc] init];
	return sSharedMusicDatabaseManager;
}

- (NSArray *) availableMusicDatabases
{
	PlugInManager *plugInManager = [PlugInManager sharedPlugInManager];
	
	NSError *error = nil;
	NSArray *availableEncoders = [plugInManager plugInsConformingToProtocol:@protocol(MusicDatabaseInterface) error:&error];
	
	return availableEncoders;	
}

- (NSBundle *) defaultMusicDatabase
{
	NSString *bundleIdentifier = [[NSUserDefaults standardUserDefaults] stringForKey:@"defaultMusicDatabase"];
	NSBundle *bundle = [[PlugInManager sharedPlugInManager] plugInForIdentifier:bundleIdentifier];
	
	// If the default wasn't found, return any available music database
	if(!bundle)
		bundle = [self.availableMusicDatabases lastObject];
	
	return bundle;
}

@end
