/*
 *  Copyright (C) 2008 - 2009 Stephen F. Booth <me@sbooth.org>
 *  All Rights Reserved
 */

#import "AlbumArtExchangeInterface.h"
#import "AlbumArtExchangeViewController.h"

@implementation AlbumArtExchangeInterface

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
	return [[AlbumArtExchangeViewController alloc] init];
}

@end
