/*
 *  Copyright (C) 2007 Stephen F. Booth <me@sbooth.org>
 *  All Rights Reserved
 */

#include "AccurateRipUtilities.h"

#include <AudioToolbox/ExtendedAudioFile.h>
#include <IOKit/storage/IOCDTypes.h>

// A block of CDDA audio consists of 2352 bytes and contains 588 frames of 16-bit 2  (!! or 4) channel audio
#define FRAMES_PER_SECTOR	588u
#define BYTES_PER_SAMPLE	(16 / 8)
#define FRAMES_PER_BLOCK	(kCDSectorSizeCDDA / (2 * BYTES_PER_SAMPLE))

// ========================================
// Verify an AudioStreamBasicDescription describes CDDA audio
// ========================================
static BOOL
streamDescriptionIsCDDA(const AudioStreamBasicDescription *asbd)
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
// Calculate and AccurateRip CRC for the file at path (must be raw 16-bit little-endian signed PCM)
// ========================================
uint32 
calculateAccurateRipCRCForFile(NSString *path, BOOL firstTrack, BOOL lastTrack)
{
	NSCParameterAssert(nil != path);
	
	uint32_t crc = 0;

	// Open the file for reading
	ExtAudioFileRef file = NULL;
	OSStatus status = ExtAudioFileOpenURL((CFURLRef)[NSURL fileURLWithPath:path], &file);
	if(noErr != status)
		return 0;
	
	// Verify the file contains CDDA audio
	AudioStreamBasicDescription fileFormat;
	UInt32 dataSize = sizeof(fileFormat);
	status = ExtAudioFileGetProperty(file, kExtAudioFileProperty_FileDataFormat, &dataSize, &fileFormat);
	if(noErr != status)
		goto cleanup;
	
	if(!streamDescriptionIsCDDA(&fileFormat))
		goto cleanup;
	
	// Determine the total number of audio frames in the file
	SInt64 totalFrames = -1;
	dataSize = sizeof(totalFrames);
	status = ExtAudioFileGetProperty(file, kExtAudioFileProperty_FileLengthFrames, &dataSize, &totalFrames);
	if(noErr != status)
		goto cleanup;
	
	// Convert the number of frames to the number of blocks (CDDA sectors)
	NSUInteger totalBlocks = (NSUInteger)(totalFrames / FRAMES_PER_BLOCK);
	NSUInteger blockNumber = 0;

	// Set up extraction buffers
	int8_t buffer [kCDSectorSizeCDDA];
	AudioBufferList bufferList;
	bufferList.mNumberBuffers = 1;
	bufferList.mBuffers[0].mNumberChannels = fileFormat.mChannelsPerFrame;
	bufferList.mBuffers[0].mData = (void *)buffer;	
	
	// Iteratively process each CDDA sector in the file
	for(;;) {
		bufferList.mBuffers[0].mDataByteSize = kCDSectorSizeCDDA;
		
		UInt32 frameCount = FRAMES_PER_SECTOR;
		status = ExtAudioFileRead(file, &frameCount, &bufferList);
		
		if(noErr != status)
			break;
		else if(FRAMES_PER_SECTOR != frameCount)
			break;
		
		crc += calculateAccurateRipCRCForBlock(buffer, blockNumber++, totalBlocks, firstTrack, lastTrack);
	}
	
cleanup:
	status = ExtAudioFileDispose(file);
/*	if(noErr != status)
		return 0;*/
	
	return crc;
}

// ========================================
// Generate an AccurateRip crc for a sector of CDDA audio
// ========================================
uint32_t
calculateAccurateRipCRCForBlock(const void *block, NSUInteger blockNumber, NSUInteger totalBlocks, BOOL firstTrack, BOOL lastTrack)
{
	NSCParameterAssert(NULL != block);
	
	if(firstTrack && 4 > blockNumber)
		return 0;
	else if(lastTrack && 6 > (totalBlocks - blockNumber))
		return 0;
	else if(firstTrack && 4 == blockNumber) {
		const uint32_t *buffer = (const uint32_t *)block;
		uint32_t sample = OSSwapHostToLittleInt32(buffer[587]);
		return 588 * (4 + 1) * sample;
	}
	else {
		const uint32_t *buffer = (const uint32_t *)block;
		uint32_t crc = 0;
		NSUInteger blockOffset = 588 * blockNumber;
		
		NSUInteger i;
		for(i = 0; i < 588; ++i)
			crc += OSSwapHostToLittleInt32(*buffer++) * ++blockOffset;
		
		return crc;
	}
}

