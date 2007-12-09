/*
 *  Copyright (C) 2007 Stephen F. Booth <me@sbooth.org>
 *  All Rights Reserved
 */

#include "AccurateRipUtilities.h"

#include <IOKit/storage/IOCDTypes.h>

#include <sys/stat.h>
#include <stdio.h>

// A block of CDDA audio consists of 2352 bytes and contains 588 frames of 16-bit 2  (!! or 4) channel audio
#define BYTES_PER_SAMPLE	(16 / 8)
#define FRAMES_PER_BLOCK	(kCDSectorSizeCDDA / (2 * BYTES_PER_SAMPLE))

// ========================================
// Calculate and AccurateRip CRC for the file at path (must be raw 16-bit little-endian signed PCM)
// ========================================
uint32 
calculateAccurateRipCRCForFile(NSString *path, BOOL firstTrack, BOOL lastTrack)
{
	NSCParameterAssert(nil != path);
	
	if(![[NSFileManager defaultManager] fileExistsAtPath:path])
		return 0;
	
	// Determine the size of the file and the number of sectors it contains
	struct stat buf;
	if(-1 == stat(path.fileSystemRepresentation, &buf))
		return 0;
	
	NSUInteger totalBlocks = (NSUInteger)(buf.st_size / kCDSectorSizeCDDA);
	
	// Open the file for reading
	NSFileHandle *fileHandle = [NSFileHandle fileHandleForReadingAtPath:path];
	if(nil == fileHandle)
		return 0;
	
	uint32_t crc = 0;
	NSUInteger blockNumber = 0;

	for(;;) {
		NSData *block = [fileHandle readDataOfLength:kCDSectorSizeCDDA];
		
		if(kCDSectorSizeCDDA != block.length)
			break;
		
		crc += calculateAccurateRipCRCForBlock(block.bytes, blockNumber++, totalBlocks, firstTrack, lastTrack);
	}
	
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

