/*
 *  Copyright (C) 2008 Stephen F. Booth <me@sbooth.org>
 *  All Rights Reserved
 */

#import "WAVEEncoderInterface.h"
#import "CoreAudioEncodeOperation.h"
#import "WAVESettingsViewController.h"

@implementation WAVEEncoderInterface

- (NSDictionary *) defaultSettings
{
	NSMutableDictionary *defaultSettings = [[NSMutableDictionary alloc] init];
	
	// WAVE container
	[defaultSettings setObject:[NSNumber numberWithInteger:kAudioFileWAVEType] forKey:kAudioFileTypeKey];

	// WAVE sourced from 16-bit, 2 channel audio (CDDA)
	AudioStreamBasicDescription waveASBD;
	memset(&waveASBD, 0, sizeof(waveASBD));
	
	waveASBD.mFormatID = kAudioFormatLinearPCM;
	waveASBD.mFormatFlags = kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked;
	
	waveASBD.mSampleRate = 44100;
	waveASBD.mChannelsPerFrame = 2;
	waveASBD.mBitsPerChannel = 16;
	
	waveASBD.mBytesPerPacket = (waveASBD.mBitsPerChannel / 8) * waveASBD.mChannelsPerFrame;
	waveASBD.mFramesPerPacket = 1;
	waveASBD.mBytesPerFrame = (waveASBD.mBitsPerChannel / 8) * waveASBD.mChannelsPerFrame;

	NSData *waveASBDData = [NSData dataWithBytes:&waveASBD length:sizeof(waveASBD)];
	
	[defaultSettings setObject:waveASBDData forKey:kStreamDescriptionKey];
	
	return defaultSettings;
}

- (NSViewController *) configurationViewController
{
	return [[WAVESettingsViewController alloc] init];
}

- (EncodingOperation *) encodingOperation
{
	return [[CoreAudioEncodeOperation alloc] init];
}

- (NSString *) pathExtensionForSettings:(NSDictionary *)settings
{
	
#pragma unused(settings)
	
	return @"wav";
}

@end
