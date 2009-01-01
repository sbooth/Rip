/*
 *  Copyright (C) 2008 - 2009 Stephen F. Booth <me@sbooth.org>
 *  All Rights Reserved
 */

#import "FreeDBDatabaseInterface.h"
#import "FreeDBQueryOperation.h"
#import "FreeDBSubmissionOperation.h"
#import "FreeDBSettingsViewController.h"

#import <AddressBook/AddressBook.h>

@implementation FreeDBDatabaseInterface

- (NSDictionary *) defaultSettings
{
	NSMutableDictionary *defaultSettings = [[NSMutableDictionary alloc] init];

	// Determine the logged-in user's primary e-mail address
	ABPerson *me = [[ABAddressBook sharedAddressBook] me];
	ABMultiValue *emailAddresses = [me valueForProperty:kABEmailProperty];
	id primaryEmailAddress = [emailAddresses valueAtIndex:[emailAddresses indexForIdentifier:[emailAddresses primaryIdentifier]]];

	[defaultSettings setObject:primaryEmailAddress forKey:@"freeDBEMailAddress"];
	[defaultSettings setObject:[NSNumber numberWithBool:NO] forKey:@"freeDBUseProxy"];
	
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

- (MusicDatabaseSubmissionOperation *) musicDatabaseSubmissionOperation
{
	return [[FreeDBSubmissionOperation alloc] init];
}

@end
