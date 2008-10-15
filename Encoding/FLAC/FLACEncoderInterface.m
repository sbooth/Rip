/*
 *  Copyright (C) 2008 Stephen F. Booth <me@sbooth.org>
 *  All Rights Reserved
 */

#import "FLACEncoderInterface.h"
#import "FLACEncodeOperation.h"
#import "FLACSettingsViewController.h"

@implementation FLACEncoderInterface

- (NSDictionary *) defaultSettings
{
	NSMutableDictionary *defaultSettings = [[NSMutableDictionary alloc] init];
	
	// Compression level 5
	[defaultSettings setObject:[NSNumber numberWithInteger:5] forKey:kFLACCompressionLevelKey];
	
	return defaultSettings;
}

- (NSViewController *) configurationViewController
{
	return [[FLACSettingsViewController alloc] init];
}

- (EncodingOperation *) encodingOperation
{
	return [[FLACEncodeOperation alloc] init];
}

- (NSString *) pathExtensionForSettings:(NSDictionary *)settings
{
	return @"flac";
}

@end
