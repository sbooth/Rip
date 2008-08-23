/*
 *  Copyright (C) 2008 Stephen F. Booth <me@sbooth.org>
 *  All Rights Reserved
 */

#import "FreeDBDatabaseInterface.h"
#import "FreeDBQueryOperation.h"
//#import "FreeDBViewController.h"

@implementation FreeDBDatabaseInterface

- (NSDictionary *) defaultSettings
{
	NSMutableDictionary *defaultSettings = [[NSMutableDictionary alloc] init];
	
//	[defaultSettings setObject:[NSNumber numberWithInteger:5] forKey:kFLACCompressionLevelKey];
	
	return defaultSettings;
}

- (NSViewController *) configurationViewController
{
//	return [[FreeDBViewController alloc] init];
	return nil;
}

- (MusicDatabaseQueryOperation *) musicDatabaseQueryOperation
{
	return [[FreeDBQueryOperation alloc] init];
}

@end
