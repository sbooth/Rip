/*
 *  Copyright (C) 2008 Stephen F. Booth <me@sbooth.org>
 *  All Rights Reserved
 */

#import "iTunesDatabaseInterface.h"
#import "iTunesQueryOperation.h"
//#import "iTunesViewController.h"

@implementation iTunesDatabaseInterface

- (NSDictionary *) defaultSettings
{
	return nil;
}

- (NSViewController *) configurationViewController
{
//	return [[iTunesViewController alloc] init];
	return nil;
}

- (MusicDatabaseQueryOperation *) musicDatabaseQueryOperation
{
	return [[iTunesQueryOperation alloc] init];
}

@end
