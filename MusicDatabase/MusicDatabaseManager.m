/*
 *  Copyright (C) 2008 Stephen F. Booth <me@sbooth.org>
 *  All Rights Reserved
 */

#import "MusicDatabaseManager.h"
#import "PlugInManager.h"
#import "MusicDatabaseInterface/MusicDatabaseInterface.h"
#import "MusicDatabaseInterface/MusicDatabaseQueryOperation.h"

// ========================================
// Sorting function for sorting bundles by music database names
// ========================================
static NSComparisonResult
musicDatabaseBundleSortFunction(id bundleA, id bundleB, void *context)
{
	
#pragma unused(context)
	
	NSCParameterAssert(nil != bundleA);
	NSCParameterAssert(nil != bundleB);
	NSCParameterAssert([bundleA isKindOfClass:[NSBundle class]]);
	NSCParameterAssert([bundleB isKindOfClass:[NSBundle class]]);
	
	NSString *bundleAName = [bundleA objectForInfoDictionaryKey:@"MusicDatabaseName"];
	NSString *bundleBName = [bundleB objectForInfoDictionaryKey:@"MusicDatabaseName"];
	
	return [bundleAName compare:bundleBName];;
}

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
		sSharedMusicDatabaseManager = [[self alloc] init];
	return sSharedMusicDatabaseManager;
}

+ (NSSet *) keyPathsForValuesAffectingDefaultMusicDatabaseSettings
{
	return [NSSet setWithObject:@"defaultMusicDatabase"];
}

- (NSArray *) availableMusicDatabases
{
	PlugInManager *plugInManager = [PlugInManager sharedPlugInManager];
	
	NSError *error = nil;
	NSArray *availableMusicDatabases = [plugInManager plugInsConformingToProtocol:@protocol(MusicDatabaseInterface) error:&error];
	
	return [availableMusicDatabases sortedArrayUsingFunction:musicDatabaseBundleSortFunction context:NULL];
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

- (void) setDefaultMusicDatabase:(NSBundle *)musicDatabase
{
	NSParameterAssert(nil != musicDatabase);
	
	// Verify this is a valid music database
	if(![self.availableMusicDatabases containsObject:musicDatabase])
		return;

	// Set this as the default music database
	NSString *bundleIdentifier = [musicDatabase bundleIdentifier];
	[[NSUserDefaults standardUserDefaults] setObject:bundleIdentifier forKey:@"defaultMusicDatabase"];

	// If no settings are present for this music database, store the defaults
	if(![[NSUserDefaults standardUserDefaults] dictionaryForKey:bundleIdentifier]) {
		// Instantiate the music database interface
		id <MusicDatabaseInterface> musicDatabaseInterface = [[[musicDatabase principalClass] alloc] init];
		
		// Grab the music database's settings dictionary
		[[NSUserDefaults standardUserDefaults] setObject:[musicDatabaseInterface defaultSettings] forKey:bundleIdentifier];
	}
}

- (NSDictionary *) defaultMusicDatabaseSettings
{
	return [self settingsForMusicDatabase:self.defaultMusicDatabase];
}

- (void) setDefaultMusicDatabaseSettings:(NSDictionary *)musicDatabaseSettings
{
	[self storeSettings:musicDatabaseSettings forMusicDatabase:self.defaultMusicDatabase];
}

- (NSDictionary *) settingsForMusicDatabase:(NSBundle *)musicDatabase
{
	NSParameterAssert(nil != musicDatabase);
	
	// Verify this is a valid music database
	if(![self.availableMusicDatabases containsObject:musicDatabase])
		return nil;

	NSString *bundleIdentifier = [musicDatabase bundleIdentifier];
	NSDictionary *musicDatabaseSettings = [[NSUserDefaults standardUserDefaults] dictionaryForKey:bundleIdentifier];
	
	// If no settings are present for this music database, use the defaults
	if(!musicDatabaseSettings) {
		// Instantiate the music database interface
		id <MusicDatabaseInterface> musicDatabaseInterface = [[[musicDatabase principalClass] alloc] init];
		
		// Grab the music database's settings dictionary
		musicDatabaseSettings = [musicDatabaseInterface defaultSettings];
		
		// Store the defaults
		if(musicDatabaseSettings)
			[[NSUserDefaults standardUserDefaults] setObject:musicDatabaseSettings forKey:bundleIdentifier];
	}

	return [musicDatabaseSettings copy];
}

- (void) storeSettings:(NSDictionary *)musicDatabaseSettings forMusicDatabase:(NSBundle *)musicDatabase
{
	NSParameterAssert(nil != musicDatabase);
	
	// Verify this is a valid music database
	if(![self.availableMusicDatabases containsObject:musicDatabase])
		return;

	NSString *bundleIdentifier = [musicDatabase bundleIdentifier];
	if(musicDatabaseSettings)
		[[NSUserDefaults standardUserDefaults] setObject:musicDatabaseSettings forKey:bundleIdentifier];
	else
		[[NSUserDefaults standardUserDefaults] removeObjectForKey:bundleIdentifier];
}

- (void) restoreDefaultSettingsForMusicDatabase:(NSBundle *)musicDatabase
{
	NSParameterAssert(nil != musicDatabase);
	
	// Verify this is a valid music database
	if(![self.availableMusicDatabases containsObject:musicDatabase])
		return;
	
	NSString *bundleIdentifier = [musicDatabase bundleIdentifier];
	
	// Instantiate the music database interface
	id <MusicDatabaseInterface> musicDatabaseInterface = [[[musicDatabase principalClass] alloc] init];
	
	// Grab the music database's settings dictionary
	NSDictionary *musicDatabaseSettings = [musicDatabaseInterface defaultSettings];
	
	// Store the defaults
	if(musicDatabaseSettings)
		[[NSUserDefaults standardUserDefaults] setObject:musicDatabaseSettings forKey:bundleIdentifier];
	else
		[[NSUserDefaults standardUserDefaults] removeObjectForKey:bundleIdentifier];
}

@end
