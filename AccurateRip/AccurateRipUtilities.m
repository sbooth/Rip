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
uint32_t 
calculateAccurateRipChecksumForFile(NSURL *fileURL, BOOL firstTrack, BOOL lastTrack)
{
	NSCParameterAssert(nil != fileURL);
	
	uint32_t checksum = 0;

	// Open the file for reading
	ExtAudioFileRef file = NULL;
	OSStatus status = ExtAudioFileOpenURL((CFURLRef)fileURL, &file);
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
uint32_t 
calculateAccurateRipChecksumForFileRegion(NSURL *fileURL, NSUInteger firstSector, NSUInteger lastSector, BOOL firstTrack, BOOL lastTrack)
{
	return calculateAccurateRipChecksumForFileRegionUsingOffset(fileURL, firstSector, lastSector, firstTrack, lastTrack, 0);
}

uint32_t 
calculateAccurateRipChecksumForFileRegionUsingOffset(NSURL *fileURL, NSUInteger firstSector, NSUInteger lastSector, BOOL firstTrack, BOOL lastTrack, NSInteger readOffsetInFrames)
{
	NSCParameterAssert(nil != fileURL);
	NSCParameterAssert(lastSector >= firstSector);
	
	uint32_t checksum = 0;
	
	// Open the file for reading
	ExtAudioFileRef file = NULL;
	OSStatus status = ExtAudioFileOpenURL((CFURLRef)fileURL, &file);
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
	
	// Determine how many frames are contained in the file
	SInt64 totalFramesInFile;
	dataSize = sizeof(totalFramesInFile);
	status = ExtAudioFileGetProperty(file, kExtAudioFileProperty_FileLengthFrames, &dataSize, &totalFramesInFile);
	if(noErr != status)
		goto cleanup;
	
	NSInteger totalSectorsInFile = (NSInteger)(totalFramesInFile / AUDIO_FRAMES_PER_CDDA_SECTOR);
	
	// With no read offset, the range of sectors that will be read won't change
	NSInteger firstSectorToRead = firstSector;
	NSInteger lastSectorToRead = lastSector;

	// Negative read offsets can easily be transformed into positive read offsets
	// For example, suppose the desired range is sectors 10 through 20 and the read offset is -600 frames.
	// This is equivalent to requesting sectors 8 - 18 with a read offset of 576 frames
	while(0 > readOffsetInFrames) {
		readOffsetInFrames += AUDIO_FRAMES_PER_CDDA_SECTOR;
		--firstSectorToRead;
		--lastSectorToRead;
	}
	
	// readOffsetInSectors is the additional number of sectors that must be extracted (at the end) to ensure a 
	// complete sector will exist when the beginning of the read is adjusted by the read offset.
	// If this value is larger than one sector, one sector less than this should be skipped at the beginning.
	// For example, suppose the desired range is sectors 1 through 10 and the read offset is 600 frames.
	// In this case readOffsetInSectors will be 2, and the actual read should be from sectors 2 through 12, with the 
	// first 12 frames of sector 2 skipped and the last 12 frames of sector 12 skipped.
	NSUInteger readOffsetInSectors = (readOffsetInFrames +  (AUDIO_FRAMES_PER_CDDA_SECTOR - 1)) / AUDIO_FRAMES_PER_CDDA_SECTOR;
	NSUInteger readOffsetInBytes = 2 * sizeof(int16_t) * readOffsetInFrames;
	
	// Adjust the sectors for the read offset
	if(1 < readOffsetInSectors) {
		firstSectorToRead += readOffsetInSectors - 1;
		
		// Skipped whole sectors are taken into account above, so subtract them out here
		while(kCDSectorSizeCDDA > readOffsetInBytes)
			readOffsetInBytes -= kCDSectorSizeCDDA;
	}
	
	lastSectorToRead += readOffsetInSectors;

	// Clamp the read range to the range of audio contained in the file
	NSUInteger sectorsOfSilenceToPrepend = 0;
	if(0 > firstSectorToRead) {
		sectorsOfSilenceToPrepend = 0 - firstSectorToRead;
		firstSectorToRead = 0;
	}
	
	NSUInteger sectorsOfSilenceToAppend = 0;
	if(lastSectorToRead > totalSectorsInFile) {
		sectorsOfSilenceToAppend = lastSectorToRead - totalSectorsInFile;
		lastSectorToRead = totalSectorsInFile;
	}
	
	// Seek to the desired starting sector, adjusting for the read offset
	// Since the AccurateRip algorithm requires whole CDDA sectors to be passed, it is easier to 
	// adjust for the read offset here and read whole sectors than to try to adjust for the read offset later
	status = ExtAudioFileSeek(file, (AUDIO_FRAMES_PER_CDDA_SECTOR * firstSectorToRead) + readOffsetInFrames);
	if(noErr != status)
		goto cleanup;
	
	// The block range is inclusive
	NSUInteger totalBlocks = lastSectorToRead - firstSectorToRead + 1;
	NSUInteger blockNumber = 0;
	
	// Set up extraction buffers
	int8_t buffer [kCDSectorSizeCDDA];
	AudioBufferList bufferList;
	bufferList.mNumberBuffers = 1;
	bufferList.mBuffers[0].mNumberChannels = fileFormat.mChannelsPerFrame;
	bufferList.mBuffers[0].mData = (void *)buffer;	

	// Prepend silence, if required
	// Since the AccurateRip checksum for silence is zero, all that must be accounted for is the block counter
	if(sectorsOfSilenceToPrepend)
		blockNumber += sectorsOfSilenceToPrepend;

	// Iteratively process each CDDA sector in the file
	NSUInteger sectorCount = totalBlocks - (sectorsOfSilenceToPrepend + sectorsOfSilenceToAppend);
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
	
	// Append silence, if required
	// Since the AccurateRip checksum for silence is zero, nothing need be done here
	if(sectorsOfSilenceToAppend)
		;

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

