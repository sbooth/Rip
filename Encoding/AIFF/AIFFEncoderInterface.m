/*
 *  Copyright (C) 2008 - 2009 Stephen F. Booth <me@sbooth.org>
 *  All Rights Reserved
 */

#import "AIFFEncoderInterface.h"
#import "AIFFEncodeOperation.h"
#import "AIFFSettingsViewController.h"

#import "EncoderInterface/EncodingPostProcessingOperation.h"

@implementation AIFFEncoderInterface

- (NSDictionary *) defaultSettings
{
	NSMutableDictionary *defaultSettings = [[NSMutableDictionary alloc] init];
	
	// AIFF container
	[defaultSettings setObject:[NSNumber numberWithInteger:kAudioFileAIFFType] forKey:kAudioFileTypeKey];

	// AIFF sourced from 16-bit, 2 channel audio (CDDA)
	AudioStreamBasicDescription aiffASBD;
	memset(&aiffASBD, 0, sizeof(aiffASBD));
	
	aiffASBD.mFormatID = kAudioFormatLinearPCM;
	aiffASBD.mFormatFlags = kAudioFormatFlagIsBigEndian | kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked;
	
	aiffASBD.mSampleRate = 44100;
	aiffASBD.mChannelsPerFrame = 2;
	aiffASBD.mBitsPerChannel = 16;
	
	aiffASBD.mBytesPerPacket = (aiffASBD.mBitsPerChannel / 8) * aiffASBD.mChannelsPerFrame;
	aiffASBD.mFramesPerPacket = 1;
	aiffASBD.mBytesPerFrame = (aiffASBD.mBitsPerChannel / 8) * aiffASBD.mChannelsPerFrame;

	NSData *AIFFASBDData = [NSData dataWithBytes:&aiffASBD length:sizeof(aiffASBD)];
	
	[defaultSettings setObject:AIFFASBDData forKey:kStreamDescriptionKey];
	
	return defaultSettings;
}

- (NSViewController *) configurationViewController
{
	return [[AIFFSettingsViewController alloc] init];
}

- (EncodingOperation *) encodingOperation
{
	return [[AIFFEncodeOperation alloc] init];
}

- (EncodingPostProcessingOperation *) encodingPostProcessingOperation
{
	return nil;
}

- (NSString *) pathExtensionForSettings:(NSDictionary *)settings
{
	
#pragma unused(settings)
	
	return @"aiff";
}

@end
