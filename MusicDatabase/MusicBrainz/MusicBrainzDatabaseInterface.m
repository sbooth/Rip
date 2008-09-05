/*
 *  Copyright (C) 2008 Stephen F. Booth <me@sbooth.org>
 *  All Rights Reserved
 */

#import "MusicBrainzDatabaseInterface.h"
#import "MusicBrainzQueryOperation.h"
#import "MusicBrainzSettingsViewController.h"

@implementation MusicBrainzDatabaseInterface

- (NSDictionary *) defaultSettings
{
	NSMutableDictionary *defaultSettings = [[NSMutableDictionary alloc] init];
	
//	[defaultSettings setObject:[NSNumber numberWithInteger:5] forKey:kFLACCompressionLevelKey];
	
	return defaultSettings;
}

- (NSViewController *) configurationViewController
{
	return [[MusicBrainzSettingsViewController alloc] init];
}

- (MusicDatabaseQueryOperation *) musicDatabaseQueryOperation
{
	return [[MusicBrainzQueryOperation alloc] init];
}

@end
