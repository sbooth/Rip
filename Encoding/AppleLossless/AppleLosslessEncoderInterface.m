/*
 *  Copyright (C) 2008 Stephen F. Booth <me@sbooth.org>
 *  All Rights Reserved
 */

#import "AppleLosslessEncoderInterface.h"
#import "AppleLosslessEncodeOperation.h"
#import "AppleLosslessSettingsViewController.h"

@implementation AppleLosslessEncoderInterface

- (NSDictionary *) defaultSettings
{
	NSMutableDictionary *defaultSettings = [[NSMutableDictionary alloc] init];
	
	// M4A container
	[defaultSettings setObject:[NSNumber numberWithInteger:kAudioFileM4AType] forKey:kAudioFileTypeKey];

	// Apple Lossless sourced from 16-bit, 2 channel audio (CDDA)
	AudioStreamBasicDescription alacASBD;
	memset(&alacASBD, 0, sizeof(alacASBD));
	
	alacASBD.mFormatID = kAudioFormatAppleLossless;
	alacASBD.mFormatFlags = kAppleLosslessFormatFlag_16BitSourceData;
	alacASBD.mSampleRate = 44100;
	alacASBD.mChannelsPerFrame = 2;
	alacASBD.mFramesPerPacket = 4096;
	
	NSData *alacASBDData = [NSData dataWithBytes:&alacASBD length:sizeof(alacASBD)];
	
	[defaultSettings setObject:alacASBDData forKey:kStreamDescriptionKey];
	
	return defaultSettings;
}

- (NSViewController *) configurationViewController
{
	return [[AppleLosslessSettingsViewController alloc] init];
}

- (EncodingOperation *) encodingOperation
{
	return [[AppleLosslessEncodeOperation alloc] init];
}

- (NSString *) pathExtensionForSettings:(NSDictionary *)settings
{
	
#pragma unused(settings)
	
	return @"m4a";
}

@end
