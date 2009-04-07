/*
 *  Copyright (C) 2008 - 2009 Stephen F. Booth <me@sbooth.org>
 *  All Rights Reserved
 */

#import "AmazonInterface.h"
#import "AmazonViewController.h"

@implementation AmazonInterface

- (NSDictionary *) defaultSettings
{
	NSMutableDictionary *defaultSettings = [[NSMutableDictionary alloc] init];
	
	return defaultSettings;
}

- (NSViewController *) configurationViewController
{
	// Nothing to configure
	return nil;
}

- (NSViewController *) metadataSourceViewController
{
	return [[AmazonViewController alloc] init];
}

@end
