/*
 *  Copyright (C) 2007 Stephen F. Booth <me@sbooth.org>
 *  All Rights Reserved
 */

#import "CDDAUtilities.h"

// ========================================
// Create an AudioStreamBasicDescription that describes CDDA audio
// ========================================
AudioStreamBasicDescription getStreamDescriptionForCDDA()
{
	AudioStreamBasicDescription cddaASBD;
	
	cddaASBD.mFormatID = kAudioFormatLinearPCM;
	cddaASBD.mFormatFlags = kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked;
	cddaASBD.mReserved = 0;
	
	cddaASBD.mSampleRate = 44100;
	cddaASBD.mChannelsPerFrame = 2;
	cddaASBD.mBitsPerChannel = 16;
	
	cddaASBD.mBytesPerFrame = cddaASBD.mChannelsPerFrame * (cddaASBD.mBitsPerChannel / 8);
	cddaASBD.mFramesPerPacket = 1;
	cddaASBD.mBytesPerPacket = cddaASBD.mBytesPerFrame * cddaASBD.mFramesPerPacket;
	
	return cddaASBD;
}

// ========================================
// Verify an AudioStreamBasicDescription describes CDDA audio
// ========================================
BOOL streamDescriptionIsCDDA(const AudioStreamBasicDescription *asbd)
{
	NSCParameterAssert(NULL != asbd);
	
	if(kAudioFormatLinearPCM != asbd->mFormatID)
		return NO;
	
	if(!(kAudioFormatFlagIsSignedInteger & asbd->mFormatFlags) || !((kAudioFormatFlagIsPacked & asbd->mFormatFlags)))
		return NO;
	
	if(44100 != asbd->mSampleRate)
		return NO;
	
	if(2 != asbd->mChannelsPerFrame)
		return NO;
	
	if(16 != asbd->mBitsPerChannel)
		return NO;
	
	return YES;
}
