/*
 *  Copyright (C) 2007 - 2008 Stephen F. Booth <me@sbooth.org>
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

// ========================================
// Utility function for adding/subtracting CDMSF structures
// ========================================
CDMSF addCDMSF(CDMSF a, CDMSF b)
{
	CDMSF result;
	memset(&result, 0, sizeof(CDMSF));
	
	result.frame = a.frame + b.frame;
	if(75 < result.frame) {
		result.frame -= 75;
		result.second += 1;
	}
	
	result.second += a.second + b.second;
	if(60 < result.second) {
		result.second -= 60;
		result.minute += 1;
	}
	
	result.minute += a.minute + b.minute;
	
	return result;
}

CDMSF subtractCDMSF(CDMSF a, CDMSF b)
{
	CDMSF result;
	memset(&result, 0, sizeof(CDMSF));
	
	NSInteger minuteDiff = a.minute - b.minute;
	NSInteger secondDiff = a.second - b.second;
	NSInteger frameDiff = a.frame - b.frame;
	
	if(0 > frameDiff) {
		frameDiff += 75;
		--secondDiff;
	}
	
	if(0 > secondDiff) {
		secondDiff += 60;
		--minuteDiff;
	}
	
	// a is larger than b, return 0 (no such thing as a negative CDMSF)
	if(0 > minuteDiff)
		return result;
	
	result.minute = minuteDiff;
	result.second = secondDiff;
	result.frame = frameDiff;
	
	return result;
}
