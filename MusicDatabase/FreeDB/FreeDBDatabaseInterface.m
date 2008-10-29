/*
 *  Copyright (C) 2008 Stephen F. Booth <me@sbooth.org>
 *  All Rights Reserved
 */

#import "FreeDBDatabaseInterface.h"
#import "FreeDBQueryOperation.h"
#import "FreeDBSettingsViewController.h"

@implementation FreeDBDatabaseInterface

- (NSDictionary *) defaultSettings
{
	NSMutableDictionary *defaultSettings = [[NSMutableDictionary alloc] init];
	
	return defaultSettings;
}

- (NSViewController *) configurationViewController
{
	return [[FreeDBSettingsViewController alloc] init];
}

- (MusicDatabaseQueryOperation *) musicDatabaseQueryOperation
{
	return [[FreeDBQueryOperation alloc] init];
}

@end
