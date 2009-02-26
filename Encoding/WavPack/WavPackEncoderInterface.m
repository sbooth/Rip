/*
 *  Copyright (C) 2009 Stephen F. Booth <me@sbooth.org>
 *  All Rights Reserved
 */

#import "WavPackEncoderInterface.h"
#import "WavPackEncodeOperation.h"
#import "WavPackSettingsViewController.h"
#import "WavPackPostProcessingOperation.h"

@implementation WavPackEncoderInterface

- (NSDictionary *) defaultSettings
{
	NSMutableDictionary *defaultSettings = [[NSMutableDictionary alloc] init];
	
	[defaultSettings setObject:[NSNumber numberWithInt:eWavPackCompressionModeNormal] forKey:kWavPackCompressionModeKey];
	[defaultSettings setObject:[NSNumber numberWithBool:YES] forKey:kWavPackComputeMD5Key];
	
	return defaultSettings;
}

- (NSViewController *) configurationViewController
{
	return [[WavPackSettingsViewController alloc] init];
}

- (EncodingOperation *) encodingOperation
{
	return [[WavPackEncodeOperation alloc] init];
}

- (EncodingPostProcessingOperation *) encodingPostProcessingOperation
{
	return [[WavPackPostProcessingOperation alloc] init];
}

- (NSString *) pathExtensionForSettings:(NSDictionary *)settings
{

#pragma unused(settings)
	
	return @"wv";
}

@end
