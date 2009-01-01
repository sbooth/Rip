/*
 *  Copyright (C) 2008 Stephen F. Booth <me@sbooth.org>
 *  All Rights Reserved
 */

#import "iTunesDatabaseInterface.h"
#import "iTunesQueryOperation.h"
#import "iTunesSettingsViewController.h"

@implementation iTunesDatabaseInterface

- (NSDictionary *) defaultSettings
{
	return nil;
}

- (NSViewController *) configurationViewController
{
	return [[iTunesSettingsViewController alloc] init];
}

- (MusicDatabaseQueryOperation *) musicDatabaseQueryOperation
{
	return [[iTunesQueryOperation alloc] init];
}

- (MusicDatabaseSubmissionOperation *) musicDatabaseSubmissionOperation
{
	return nil;
}

@end
