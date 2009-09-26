/*
 *  Copyright (C) 2007 - 2009 Stephen F. Booth <me@sbooth.org>
 *  All Rights Reserved
 */

#import "AccurateRipUtilities.h"
#import "CDDAUtilities.h"

#include <AudioToolbox/AudioFile.h>
#include <IOKit/storage/IOCDTypes.h>

// ========================================
// Calculate the AccurateRip checksum for the file at path
// ========================================
uint32_t 
calculateAccurateRipChecksumForFile(NSURL *fileURL, BOOL isFirstTrack, BOOL isLastTrack)
{
	NSCParameterAssert(nil != fileURL);
	
	uint32_t checksum = 0;

	// Open the file for reading
	AudioFileID file = NULL;
	OSStatus status = AudioFileOpenURL((CFURLRef)fileURL, fsRdPerm, kAudioFileWAVEType, &file);
	if(noErr != status)
		return 0;
	
	// Verify the file contains CDDA audio
	AudioStreamBasicDescription fileFormat;
	UInt32 dataSize = sizeof(fileFormat);
	status = AudioFileGetProperty(file, kAudioFilePropertyDataFormat, &dataSize, &fileFormat);
	if(noErr != status)
		goto cleanup;
	
	if(!streamDescriptionIsCDDA(&fileFormat))
		goto cleanup;
	
	// Determine the total number of audio packets (frames) in the file
	UInt64 totalPackets;
	dataSize = sizeof(totalPackets);
	status = AudioFileGetProperty(file, kAudioFilePropertyAudioDataPacketCount, &dataSize, &totalPackets);
	if(noErr != status)
		goto cleanup;
	
	// Convert the number of frames to the number of blocks (CDDA sectors)
	NSUInteger totalBlocks = (NSUInteger)(totalPackets / AUDIO_FRAMES_PER_CDDA_SECTOR);
	NSUInteger blockNumber = 0;

	// Set up extraction buffers
	int8_t buffer [kCDSectorSizeCDDA];
	
	// Iteratively process each CDDA sector in the file
	for(;;) {
		
		UInt32 byteCount = kCDSectorSizeCDDA;
		UInt32 packetCount = AUDIO_FRAMES_PER_CDDA_SECTOR;
		SInt64 startingPacket = blockNumber * AUDIO_FRAMES_PER_CDDA_SECTOR;
		
		status = AudioFileReadPackets(file, false, &byteCount, NULL, startingPacket, &packetCount, buffer);
		
		if(noErr != status || kCDSectorSizeCDDA != byteCount || AUDIO_FRAMES_PER_CDDA_SECTOR != packetCount)
			break;
		
		checksum += calculateAccurateRipChecksumForBlock(buffer, blockNumber++, totalBlocks, isFirstTrack, isLastTrack);
	}
	
cleanup:
	/*status = */AudioFileClose(file);
	
	return checksum;
}

// ========================================
// Calculate the AccurateRip checksum for the specified range of CDDA sectors file at path
// ========================================
uint32_t 
calculateAccurateRipChecksumForFileRegion(NSURL *fileURL, NSRange sectorsToProcess, BOOL isFirstTrack, BOOL isLastTrack)
{
	return calculateAccurateRipChecksumForFileRegionUsingOffset(fileURL, sectorsToProcess, isFirstTrack, isLastTrack, 0);
}

uint32_t 
calculateAccurateRipChecksumForFileRegionUsingOffset(NSURL *fileURL, NSRange sectorsToProcess, BOOL isFirstTrack, BOOL isLastTrack, NSInteger readOffsetInFrames)
{
	NSCParameterAssert(nil != fileURL);
	
	uint32_t checksum = 0;
	
	// Open the file for reading
	AudioFileID file = NULL;
	OSStatus status = AudioFileOpenURL((CFURLRef)fileURL, fsRdPerm, kAudioFileWAVEType, &file);
	if(noErr != status)
		return 0;
	
	// Verify the file contains CDDA audio
	AudioStreamBasicDescription fileFormat;
	UInt32 dataSize = sizeof(fileFormat);
	status = AudioFileGetProperty(file, kAudioFilePropertyDataFormat, &dataSize, &fileFormat);
	if(noErr != status)
		goto cleanup;
	
	if(!streamDescriptionIsCDDA(&fileFormat))
		goto cleanup;
	
	// Determine the total number of audio packets (frames) in the file
	UInt64 totalPacketsInFile;
	dataSize = sizeof(totalPacketsInFile);
	status = AudioFileGetProperty(file, kAudioFilePropertyAudioDataPacketCount, &dataSize, &totalPacketsInFile);
	if(noErr != status)
		goto cleanup;
	
	NSInteger totalSectorsInFile = (NSInteger)(totalPacketsInFile / AUDIO_FRAMES_PER_CDDA_SECTOR);
	
	// With no read offset, the range of sectors that will be read won't change
	NSInteger firstSectorToRead = sectorsToProcess.location;
	NSInteger lastSectorToRead = sectorsToProcess.location + sectorsToProcess.length - 1;

	// Negative read offsets can easily be transformed into positive read offsets
	// For example, suppose the desired range is sectors 10 through 20 and the read offset is -600 frames.
	// This is equivalent to requesting sectors 8 - 18 with a read offset of 576 frames
	while(0 > readOffsetInFrames) {
		readOffsetInFrames += AUDIO_FRAMES_PER_CDDA_SECTOR;
		--firstSectorToRead;
		--lastSectorToRead;
	}
	
	// Adjust the sectors which will be read for read offsets equal to or larger than one sector
	while(AUDIO_FRAMES_PER_CDDA_SECTOR <= readOffsetInFrames) {
		readOffsetInFrames -= AUDIO_FRAMES_PER_CDDA_SECTOR;
		++firstSectorToRead;
		++lastSectorToRead;
	}

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
	
	// The number of complete blocks to be read; the sector range is inclusive
	NSUInteger totalBlocks = lastSectorToRead - firstSectorToRead + 1;
	NSUInteger blockNumber = 0;
	
	int8_t buffer [kCDSectorSizeCDDA];

	// Prepend silence, if required
	// Since the AccurateRip checksum for silence is zero, all that must be accounted for is the block counter
	if(sectorsOfSilenceToPrepend)
		blockNumber += sectorsOfSilenceToPrepend;

	// Adjust the starting packet for the read offset
	SInt64 startingPacket = (firstSectorToRead * AUDIO_FRAMES_PER_CDDA_SECTOR) + readOffsetInFrames;
	
	// Iteratively process each CDDA sector in the file
	NSUInteger sectorCount = totalBlocks - (sectorsOfSilenceToPrepend + sectorsOfSilenceToAppend);
	while(sectorCount--) {
		
		UInt32 byteCount = kCDSectorSizeCDDA;
		UInt32 packetCount = AUDIO_FRAMES_PER_CDDA_SECTOR;
		
		status = AudioFileReadPackets(file, false, &byteCount, NULL, startingPacket, &packetCount, buffer);
		
		if(noErr != status || kCDSectorSizeCDDA != byteCount || AUDIO_FRAMES_PER_CDDA_SECTOR != packetCount)
			break;
		
		checksum += calculateAccurateRipChecksumForBlock(buffer, blockNumber++, totalBlocks, isFirstTrack, isLastTrack);
		
		startingPacket += packetCount;
	}
	
	// Append silence, if required
	// Since the AccurateRip checksum for silence is zero, nothing need be done here
//	if(sectorsOfSilenceToAppend)
//		;

cleanup:
	/*status = */AudioFileClose(file);
	
	return checksum;
}

// ========================================
// Generate the AccurateRip CRC for a sector of CDDA audio
// ========================================
uint32_t
calculateAccurateRipChecksumForBlock(const void *block, NSUInteger blockNumber, NSUInteger totalBlocks, BOOL isFirstTrack, BOOL isLastTrack)
{
	NSCParameterAssert(NULL != block);

	if(isFirstTrack && 4 > blockNumber)
		return 0;
	else if(isLastTrack && 6 > (totalBlocks - blockNumber))
		return 0;
	else if(isFirstTrack && 4 == blockNumber) {
		const uint32_t *buffer = (const uint32_t *)block;
		uint32_t sample = OSSwapHostToLittleInt32(buffer[AUDIO_FRAMES_PER_CDDA_SECTOR - 1]);
		return AUDIO_FRAMES_PER_CDDA_SECTOR * (4 + 1) * sample;
	}
	else {
		const uint32_t *buffer = (const uint32_t *)block;
		uint32_t checksum = 0;
		uint32_t blockOffset = (uint32_t)(AUDIO_FRAMES_PER_CDDA_SECTOR * blockNumber);
		
		for(NSUInteger i = 0; i < AUDIO_FRAMES_PER_CDDA_SECTOR; ++i)
			checksum += OSSwapHostToLittleInt32(*buffer++) * ++blockOffset;

		return checksum;
	}
}

/*
 Special thanks to Gregory S. Chudov for the following:
 
 AccurateRip CRC is linear. Here is what i mean by that: 
 
 Let's say we have a block of data somewhere in the middle of the track, starting from sample #N;
 Let's calculate what does it contrubute to a track ArCRC, and call it S[0]:
 S[0] = sum ((i + N)*sample[i]);
 
 Now we want to calculate what does the same block of data contribute to the ArCRC offsetted by X, and call it S[X]:
 S[X] = sum ((i + N + X)*sample[i]);
 
 Obviously, S[X] = S[0] + X * sum (sample[i]);
 
 So in fact, we only need to calculate two base sums:
 SA = sum (i * sample[i]);
 SB = sum (sample[i]);
 
 Then we can calculate all offsetted CRCs easily:
 S[0] = SA + N * SB;
 ...
 S[X] = SA + (N+X) * SB;
 
 So instead of double cycle (for each offset process each sample) you can have two consecutive cycles, first for samples, second for offsets.
 You can calculate thousands of offsetted CRCs for the price of two.
 
 The tricky part is when you process the samples which are close to the track boundaries.
 For those samples you'll have to revert for the old algorithm. 
 */
// ========================================
// Calculate the AccurateRip checksums for the file at path
// ========================================
NSData * 
calculateAccurateRipChecksumsForTrackInFile(NSURL *fileURL, NSRange trackSectors, BOOL isFirstTrack, BOOL isLastTrack, NSUInteger maximumOffsetInBlocks, BOOL assumeMissingSectorsAreSilence)
{
	NSCParameterAssert(nil != fileURL);
	
	// The number of audio frames in the track
	NSUInteger totalFramesInTrack = trackSectors.length * AUDIO_FRAMES_PER_CDDA_SECTOR;
	
	// Checksums will be tracked in this array
	uint32_t *checksums = NULL;
	
	// Open the file for reading
	AudioFileID file = NULL;
	OSStatus status = AudioFileOpenURL((CFURLRef)fileURL, fsRdPerm, kAudioFileWAVEType, &file);
	if(noErr != status)
		return nil;
	
	// Verify the file contains CDDA audio
	AudioStreamBasicDescription fileFormat;
	UInt32 dataSize = sizeof(fileFormat);
	status = AudioFileGetProperty(file, kAudioFilePropertyDataFormat, &dataSize, &fileFormat);
	if(noErr != status)
		goto cleanup;
	
	if(!streamDescriptionIsCDDA(&fileFormat))
		goto cleanup;
	
	// Determine the total number of audio packets (frames) in the file
	UInt64 totalPackets;
	dataSize = sizeof(totalPackets);
	status = AudioFileGetProperty(file, kAudioFilePropertyAudioDataPacketCount, &dataSize, &totalPackets);
	if(noErr != status)
		goto cleanup;
	
	// Convert the number of frames to the number of blocks (CDDA sectors)
	NSUInteger totalBlocks = (NSUInteger)(totalPackets / AUDIO_FRAMES_PER_CDDA_SECTOR);
	
	// Determine if any sectors are missing at the beginning or end
	NSUInteger missingSectorsAtStart = 0;
	NSUInteger missingSectorsAtEnd = 0;
	if(trackSectors.length + (2 * maximumOffsetInBlocks) > totalBlocks) {
		NSUInteger missingSectors = trackSectors.length + (2 * maximumOffsetInBlocks) - totalBlocks;
		
		if(maximumOffsetInBlocks > trackSectors.location)
			missingSectorsAtStart = maximumOffsetInBlocks - trackSectors.location;

		missingSectorsAtEnd = missingSectors - missingSectorsAtStart;		
	}
	
	// If there aren't enough sectors (blocks) in the file, it can't be processed
	if(totalBlocks < trackSectors.length)
		goto cleanup;

	// Missing non-track sectors may be allowed
	if(!assumeMissingSectorsAreSilence && (missingSectorsAtStart || missingSectorsAtEnd))
		goto cleanup;

	NSUInteger maximumOffsetInFrames = maximumOffsetInBlocks * AUDIO_FRAMES_PER_CDDA_SECTOR;
	
	// The inclusive range of blocks making up the track
	NSUInteger firstFileBlockForTrack = trackSectors.location;
	NSUInteger lastFileBlockForTrack = firstFileBlockForTrack + trackSectors.length - 1;
	
	// Only blocks in the middle of the track can be processed using the fast offset calculation algorithm
	NSUInteger firstFileBlockForFastProcessing;
	if(isFirstTrack)
		firstFileBlockForFastProcessing = firstFileBlockForTrack + (5 > maximumOffsetInBlocks ? 5 : maximumOffsetInBlocks);
	else
		firstFileBlockForFastProcessing = firstFileBlockForTrack + maximumOffsetInBlocks;
	
	NSUInteger lastFileBlockForFastProcessing;
	if(isLastTrack)
		lastFileBlockForFastProcessing = lastFileBlockForTrack - (5 > maximumOffsetInBlocks ? 5 : maximumOffsetInBlocks);
	else
		lastFileBlockForFastProcessing = lastFileBlockForTrack - maximumOffsetInBlocks;
	
	// Set up the checksum buffer
	checksums = calloc((2 * maximumOffsetInFrames) + 1, sizeof(uint32_t));
	
	// The extraction buffer
	int8_t buffer [kCDSectorSizeCDDA];
	
	// Iteratively process each CDDA sector of interest in the file
	for(NSUInteger fileBlockNumber = firstFileBlockForTrack - maximumOffsetInBlocks + missingSectorsAtStart; fileBlockNumber <= lastFileBlockForTrack + maximumOffsetInBlocks - missingSectorsAtEnd; ++fileBlockNumber) {
		UInt32 byteCount = kCDSectorSizeCDDA;
		UInt32 packetCount = AUDIO_FRAMES_PER_CDDA_SECTOR;
		SInt64 startingPacket = fileBlockNumber * AUDIO_FRAMES_PER_CDDA_SECTOR;
		
		status = AudioFileReadPackets(file, false, &byteCount, NULL, startingPacket, &packetCount, buffer);
		
		if(noErr != status || kCDSectorSizeCDDA != byteCount || AUDIO_FRAMES_PER_CDDA_SECTOR != packetCount)
			break;
		
		NSInteger trackBlockNumber = fileBlockNumber - firstFileBlockForTrack;
		NSInteger trackFrameNumber = trackBlockNumber * AUDIO_FRAMES_PER_CDDA_SECTOR;
		const uint32_t *sampleBuffer = (const uint32_t *)buffer;			
		
		// Sectors in the middle of the track can be processed quickly
		if(fileBlockNumber >= firstFileBlockForFastProcessing && fileBlockNumber <= lastFileBlockForFastProcessing) {
			uint32_t sumOfSamples = 0;
			uint32_t sumOfSamplesAndPositions = 0;
			
			// Calculate two sums for the audio
			for(NSUInteger frameIndex = 0; frameIndex < AUDIO_FRAMES_PER_CDDA_SECTOR; ++frameIndex) {
				uint32_t sample = OSSwapHostToLittleInt32(*sampleBuffer++);
				
				sumOfSamples += sample;
				sumOfSamplesAndPositions += (uint32_t)(sample * (frameIndex + 1));
			}
			
			for(NSInteger offsetIndex = -maximumOffsetInFrames; offsetIndex <= (NSInteger)maximumOffsetInFrames; ++offsetIndex)
				checksums[offsetIndex + maximumOffsetInFrames] += sumOfSamplesAndPositions + (uint32_t)(((trackFrameNumber - offsetIndex) * sumOfSamples));
		}
		// Sectors at the beginning or end of the track or disc must be handled specially
		// This could be optimized but for now it uses the normal method of Accurate Rip checksum calculation
		else {
			for(NSUInteger frameIndex = 0; frameIndex < AUDIO_FRAMES_PER_CDDA_SECTOR; ++frameIndex) {
				uint32_t sample = OSSwapHostToLittleInt32(*sampleBuffer++);
				
				for(NSInteger offsetIndex = -maximumOffsetInFrames; offsetIndex <= (NSInteger)maximumOffsetInFrames; ++offsetIndex) {
					// Current frame is the track's frame number in the context of the current offset
					NSInteger currentFrame = trackFrameNumber + (NSInteger)frameIndex - offsetIndex;
					
					// The current frame is in the skipped area of the first track on the disc
					if(isFirstTrack && ((5 * AUDIO_FRAMES_PER_CDDA_SECTOR) - 1) > currentFrame)
						;
					// The current frame is in the skipped area of the last track on the disc
					else if(isLastTrack && (5 * AUDIO_FRAMES_PER_CDDA_SECTOR) >= (totalFramesInTrack - currentFrame))
						;
					// The current frame is in the previous track
					else if(0 > currentFrame)
						;
					// The current frame is in the next track
					else if(currentFrame >= (NSInteger)totalFramesInTrack)
						;
					// Process the sample
					else
						checksums[offsetIndex + maximumOffsetInFrames] += sample * (uint32_t)(currentFrame + 1);
				}
			}
		}
	}
	
cleanup:
	/*status = */AudioFileClose(file);
	
	if(checksums)
		return [NSData dataWithBytesNoCopy:checksums length:(((2 * maximumOffsetInFrames) + 1) * sizeof(uint32_t))];
	else
		return nil;
}
