/*
 *  Copyright (C) 2007 Stephen F. Booth <me@sbooth.org>
 *  All Rights Reserved
 */

#import "AccurateRipUtilities.h"
#import "CDDAUtilities.h"

#include <AudioToolbox/ExtendedAudioFile.h>
#include <IOKit/storage/IOCDTypes.h>

// ========================================
// Calculate the AccurateRip checksum for the file at path
// ========================================
uint32 
calculateAccurateRipChecksumForFile(NSString *path, BOOL firstTrack, BOOL lastTrack)
{
	NSCParameterAssert(nil != path);
	
	uint32_t checksum = 0;

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
	NSUInteger totalBlocks = (NSUInteger)(totalFrames / AUDIO_FRAMES_PER_CDDA_SECTOR);
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
		
		UInt32 frameCount = AUDIO_FRAMES_PER_CDDA_SECTOR;
		status = ExtAudioFileRead(file, &frameCount, &bufferList);
		
		if(noErr != status)
			break;
		else if(AUDIO_FRAMES_PER_CDDA_SECTOR != frameCount)
			break;
		
		checksum += calculateAccurateRipChecksumForBlock(buffer, blockNumber++, totalBlocks, firstTrack, lastTrack);
	}
	
cleanup:
	status = ExtAudioFileDispose(file);
/*	if(noErr != status)
		return 0;*/
	
	return checksum;
}

// ========================================
// Calculate the AccurateRip checksum for the specified range of CDDA sectors file at path
// ========================================
uint32 
calculateAccurateRipChecksumForFileRegion(NSString *path, NSUInteger firstSector, NSUInteger lastSector, BOOL firstTrack, BOOL lastTrack)
{
	NSCParameterAssert(nil != path);
	NSCParameterAssert(lastSector >= firstSector);
	
	uint32_t checksum = 0;
	
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
	
	// For some reason seeking fails if the client data format is not set
	AudioStreamBasicDescription cddaDescription = getStreamDescriptionForCDDA();
	status = ExtAudioFileSetProperty(file, kExtAudioFileProperty_ClientDataFormat, sizeof(cddaDescription), &cddaDescription);
	if(noErr != status)
		goto cleanup;
	
	// Seek to the desired starting sector
	status = ExtAudioFileSeek(file, AUDIO_FRAMES_PER_CDDA_SECTOR * firstSector);
	if(noErr != status)
		goto cleanup;
	
	// The block range is inclusive
	NSUInteger totalBlocks = lastSector - firstSector + 1;
	NSUInteger blockNumber = 0;
	
	// Set up extraction buffers
	int8_t buffer [kCDSectorSizeCDDA];
	AudioBufferList bufferList;
	bufferList.mNumberBuffers = 1;
	bufferList.mBuffers[0].mNumberChannels = fileFormat.mChannelsPerFrame;
	bufferList.mBuffers[0].mData = (void *)buffer;	
	
	// Iteratively process each CDDA sector in the file
	NSUInteger sectorCount = totalBlocks;
	while(sectorCount--) {
		bufferList.mBuffers[0].mDataByteSize = kCDSectorSizeCDDA;
		
		UInt32 frameCount = AUDIO_FRAMES_PER_CDDA_SECTOR;
		status = ExtAudioFileRead(file, &frameCount, &bufferList);
		
		if(noErr != status)
			break;
		else if(AUDIO_FRAMES_PER_CDDA_SECTOR != frameCount)
			break;
		
		checksum += calculateAccurateRipChecksumForBlock(buffer, blockNumber++, totalBlocks, firstTrack, lastTrack);
	}
	
cleanup:
	status = ExtAudioFileDispose(file);
/*	if(noErr != status)
		return 0;*/
	
	return checksum;
}

// ========================================
// Generate the AccurateRip CRC for a sector of CDDA audio
// ========================================
uint32_t
calculateAccurateRipChecksumForBlock(const void *block, NSUInteger blockNumber, NSUInteger totalBlocks, BOOL firstTrack, BOOL lastTrack)
{
	NSCParameterAssert(NULL != block);

	if(firstTrack && 4 > blockNumber)
		return 0;
	else if(lastTrack && 6 > (totalBlocks - blockNumber))
		return 0;
	else if(firstTrack && 4 == blockNumber) {
		const uint32_t *buffer = (const uint32_t *)block;
		uint32_t sample = OSSwapHostToLittleInt32(buffer[AUDIO_FRAMES_PER_CDDA_SECTOR - 1]);
		return AUDIO_FRAMES_PER_CDDA_SECTOR * (4 + 1) * sample;
	}
	else {
		const uint32_t *buffer = (const uint32_t *)block;
		uint32_t checksum = 0;
		NSUInteger blockOffset = AUDIO_FRAMES_PER_CDDA_SECTOR * blockNumber;
		
		NSUInteger i;
		for(i = 0; i < AUDIO_FRAMES_PER_CDDA_SECTOR; ++i)
			checksum += OSSwapHostToLittleInt32(*buffer++) * ++blockOffset;

		return checksum;
	}
}

