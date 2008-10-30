/*
 *  Copyright (C) 2007 - 2008 Stephen F. Booth <me@sbooth.org>
 *  All Rights Reserved
 */

#import "ExtractionOperation.h"
#import "SectorRange.h"
#import "SessionDescriptor.h"
#import "BitArray.h"
#import "Drive.h"
#import "CDDAUtilities.h"

#include <IOKit/storage/IOCDTypes.h>
#include <AudioToolbox/AudioFile.h>
#include <CommonCrypto/CommonDigest.h>

// Keep reads to approximately 2 MB in size (2352 + 294 + 16 bytes are necessary for each sector)
#define BUFFER_SIZE_IN_SECTORS 775u

// ========================================
// Delete the specified number of bits from the beginning of buffer
// ========================================
static void
zeroLeadingBitsOfBufferInPlace(void *buffer, 
							   NSUInteger numberOfBitsToZero)
{
	NSCParameterAssert(NULL != buffer);
	
	NSUInteger bytesToZero = numberOfBitsToZero / 8;
	NSUInteger bitsToZero = numberOfBitsToZero % 8;
	
	uint8_t *alias = (uint8_t *)buffer;

	// Zero the whole undesired bytes
	memset(buffer, 0, bytesToZero);

	alias += bytesToZero;
	
	// Zero the remaining undesired bits
	switch(bitsToZero) {
		case 0:		*alias++ &= 0xFF;		break;
		case 1:		*alias++ &= 0x7F;		break;
		case 2:		*alias++ &= 0x3F;		break;
		case 3:		*alias++ &= 0x1F;		break;
		case 4:		*alias++ &= 0x0F;		break;
		case 5:		*alias++ &= 0x07;		break;
		case 6:		*alias++ &= 0x03;		break;
		case 7:		*alias++ &= 0x01;		break;
	}
}

// ========================================
// Delete the specified number of bits from the beginning of buffer
// ========================================
static void
zeroTrailingBitsOfBufferInPlace(void *buffer, 
								NSUInteger length,
								NSUInteger numberOfBitsToZero)
{
	NSCParameterAssert(NULL != buffer);
	
	NSUInteger bytesToZero = numberOfBitsToZero / 8;
	NSUInteger bitsToZero = numberOfBitsToZero % 8;

	uint8_t *alias = (uint8_t *)buffer;
	alias += (length - bytesToZero - 1);

	// Mask out the undesired bits
	switch(bitsToZero) {
		case 0:		*alias++ &= 0xFF;		break;
		case 1:		*alias++ &= 0xFE;		break;
		case 2:		*alias++ &= 0xFC;		break;
		case 3:		*alias++ &= 0xF8;		break;
		case 4:		*alias++ &= 0xF0;		break;
		case 5:		*alias++ &= 0xE0;		break;
		case 6:		*alias++ &= 0xC0;		break;
		case 7:		*alias++ &= 0x80;		break;
	}

	// Zero the remaining whole undesired bytes
	memset(alias, 0, bytesToZero);
}

@interface ExtractionOperation ()
@property (copy) SectorRange * sectorsRead;
@property (copy) NSError * error;
@property (copy) NSIndexSet * blockErrorFlags;
@property (copy) NSDictionary * errorFlags;
@property (copy) NSString * MD5;
@property (copy) NSString * SHA1;
@property (assign) float fractionComplete;
@property (assign) NSDate * startTime;
@end

@interface ExtractionOperation (Private)
- (void) setErrorFlags:(const uint8_t *)errorFlags forSectorRange:(SectorRange *)range;
@end

@implementation ExtractionOperation

@synthesize disk = _disk;
@synthesize sectors = _sectors;
@synthesize allowedSectors = _allowedSectors;
@synthesize sectorsRead = _sectorsRead;
@synthesize trackIDs = _trackIDs;
@synthesize error = _error;
@synthesize blockErrorFlags = _blockErrorFlags;
@synthesize errorFlags = _errorFlags;
@synthesize URL = _URL;
@synthesize readOffset = _readOffset;
@synthesize MD5 = _MD5;
@synthesize SHA1 = _SHA1;
@synthesize fractionComplete = _fractionComplete;
@synthesize startTime = _startTime;

- (id) initWithDADiskRef:(DADiskRef)disk
{
	NSParameterAssert(NULL != disk);
	
	if((self = [super init]))
		self.disk = disk;
	return self;
}
		
- (void) main
{
	NSAssert(NULL != self.disk, @"self.disk may not be NULL");
	NSAssert(nil != self.sectors, @"self.sectors may not be nil");
	NSAssert(nil != self.URL, @"self.URL may not be nil");

	// Record the start time
	self.startTime = [NSDate date];
	
	// ========================================
	// GENERAL SETUP

	// Open the CD media for reading
	Drive *drive = [[Drive alloc] initWithDADiskRef:self.disk];
	if(![drive openDevice]) {
		self.error = drive.error;
		return;
	}

	// Set up the ASBD for CDDA audio
	const AudioStreamBasicDescription cddaASBD = getStreamDescriptionForCDDA();
	
	// Create and open the output file, overwriting if it exists
	AudioFileID file = NULL;
	OSStatus status = AudioFileCreateWithURL((CFURLRef)self.URL, kAudioFileWAVEType, &cddaASBD, kAudioFileFlags_EraseFile, &file);
	if(noErr != status) {
		self.error = [NSError errorWithDomain:NSOSStatusErrorDomain code:status userInfo:nil];
		goto cleanup;
	}

	// Allocate the extraction buffers
	__strong int8_t *buffer = NSAllocateCollectable(BUFFER_SIZE_IN_SECTORS * (kCDSectorSizeCDDA + kCDSectorSizeErrorFlags/* + kCDSectorSizeQSubchannel*/), 0);
	__strong int8_t *audioBuffer = NSAllocateCollectable(BUFFER_SIZE_IN_SECTORS * kCDSectorSizeCDDA, 0);
	__strong uint8_t *c2Buffer = NSAllocateCollectable(BUFFER_SIZE_IN_SECTORS * kCDSectorSizeErrorFlags, 0);
//	__strong int8_t *qBuffer = NSAllocateCollectable(BUFFER_SIZE_IN_SECTORS * kCDSectorSizeQSubchannel, 0);
	int8_t *alias = NULL;
	
	if(NULL == buffer || NULL == audioBuffer || NULL == c2Buffer/* || NULL == qBuffer*/) {
		self.error = [NSError errorWithDomain:NSPOSIXErrorDomain code:ENOMEM userInfo:nil];
		goto cleanup;
	}
	
	// Initialize the MD5 and SHA1 checksums
	CC_MD5_CTX md5;
	CC_MD5_Init(&md5);
	
	CC_SHA1_CTX sha1;
	CC_SHA1_Init(&sha1);

	// ========================================
	// SETUP FOR READ OFFSET HANDLING
	
	// With no read offset, the range of sectors that will be extracted won't change
	NSInteger firstSectorToRead = self.sectors.firstSector;
	NSInteger lastSectorToRead = self.sectors.lastSector;

	// Handle the read offset, if specified
	NSInteger readOffsetInFrames = 0;
	if(self.readOffset)
		readOffsetInFrames = self.readOffset.integerValue;
	
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

	// Determine the first sector that can be legally read (so as not to over-read the lead in)
	NSInteger firstPermissibleSector = 0;
	if(self.allowedSectors)
		firstPermissibleSector = self.allowedSectors.firstSector;
	
	// Determine the last sector that can be legally read (so as not to over-read the lead out)
	NSInteger lastPermissibleSector = NSIntegerMax;
	if(self.allowedSectors)
		lastPermissibleSector = self.allowedSectors.lastSector;
	
	// Clamp the read range to the specified sector limitations
	NSUInteger sectorsOfSilenceToPrepend = 0;
	if(firstSectorToRead < firstPermissibleSector) {
		sectorsOfSilenceToPrepend = firstPermissibleSector - firstSectorToRead;
		firstSectorToRead = firstPermissibleSector;
	}
	
	NSUInteger sectorsOfSilenceToAppend = 0;
	if(lastSectorToRead > lastPermissibleSector) {
		sectorsOfSilenceToAppend = lastSectorToRead - lastPermissibleSector;
		lastSectorToRead = lastPermissibleSector;
	}

	// Store the sectors that will actually be read
	self.sectorsRead = [[SectorRange alloc] initWithFirstSector:firstSectorToRead lastSector:lastSectorToRead];
	
	// Setup C2 block error tracking
	_blockErrorFlags = [NSMutableIndexSet indexSet];
	_errorFlags = [NSMutableDictionary dictionary];
	
	// Housekeeping setup
	self.fractionComplete = 0;
	SInt64 packetNumber = 0;
	
	// ========================================
	// EXTRACTION PHASE 1: PREPEND SILENCE AS NECESSARY
	
	// Prepend silence, adjusted for the read offset, if required
	if(sectorsOfSilenceToPrepend) {
		memset(buffer, 0, sectorsOfSilenceToPrepend * kCDSectorSizeCDDA);

		NSData *audioData = [NSData dataWithBytesNoCopy:(buffer + readOffsetInBytes)
												 length:((kCDSectorSizeCDDA * sectorsOfSilenceToPrepend) - readOffsetInBytes)
										   freeWhenDone:NO];

		// Write the silence to the output file
		UInt32 packetCount = audioData.length / cddaASBD.mBytesPerPacket;
		status = AudioFileWritePackets(file, false, audioData.length, NULL, packetNumber, &packetCount, audioData.bytes);
		if(noErr != status) {
			self.error = [NSError errorWithDomain:NSOSStatusErrorDomain code:status userInfo:nil];
			goto cleanup;
		}

		// Update the MD5 and SHA1 digests
		CC_MD5_Update(&md5, audioData.bytes, audioData.length);
		CC_SHA1_Update(&sha1, audioData.bytes, audioData.length);
		
		// Housekeeping
		packetNumber += packetCount;
	}
	
	// ========================================
	// EXTRACTION PHASE 2: ITERATIVE READS FROM CD MEDIA

	// Iteratively extract the desired sector range
	NSUInteger sectorsRemaining = self.sectorsRead.length;
	while(0 < sectorsRemaining) {
		// Set up the parameters for this read
		NSUInteger startSector = self.sectorsRead.firstSector + self.sectorsRead.length - sectorsRemaining;
		NSUInteger sectorCount = MIN(BUFFER_SIZE_IN_SECTORS, sectorsRemaining);
		SectorRange *readRange = [SectorRange sectorRangeWithFirstSector:startSector sectorCount:sectorCount];

		// Read from the CD media
		NSUInteger sectorsRead = [drive readAudioAndErrorFlags:buffer sectorRange:readRange];
		
		// Verify the requested sectors were read
		if(0 == sectorsRead) {
			self.error = drive.error;
			goto cleanup;
		}
		else if(sectorsRead != sectorCount) {
			self.error = [NSError errorWithDomain:NSPOSIXErrorDomain code:EIO userInfo:nil];
			goto cleanup;
		}
		
		// Copy the audio and C2 data to their respective buffers
		NSUInteger i;
		for(i = 0; i < sectorsRead; ++i) {
			alias = buffer + (i * (kCDSectorSizeCDDA + kCDSectorSizeErrorFlags));
			
			memcpy(audioBuffer + (i * kCDSectorSizeCDDA), alias, kCDSectorSizeCDDA);
			memcpy(c2Buffer + (i * kCDSectorSizeErrorFlags), alias + kCDSectorSizeCDDA, kCDSectorSizeErrorFlags);				
			//memcpy(qBuffer + (i * kCDSectorSizeQSubchannel), alias + kCDSectorSizeCDDA + kCDSectorSizeErrorFlags, kCDSectorSizeQSubchannel);
		}

		NSData *audioData = nil;
		
		// Audio data is offset by the number of bytes corresponding to the read offset in sample frames
		// If sectors of silence were prepended or will be appended, the read offset is taken into account there
		if(!sectorsOfSilenceToPrepend && readRange.firstSector == self.sectorsRead.firstSector) {
			audioData = [NSData dataWithBytesNoCopy:(audioBuffer + readOffsetInBytes)
											 length:((kCDSectorSizeCDDA * sectorsRead) - readOffsetInBytes)
									   freeWhenDone:NO];

			// Discard any C2 error bits corresponding to discarded samples in the read offset
			zeroLeadingBitsOfBufferInPlace(c2Buffer, readOffsetInFrames);
		}
		// If this is the last read, remove the last readOffset sample frames of data
		else if(!sectorsOfSilenceToAppend && readRange.lastSector == self.sectorsRead.lastSector) {
			audioData = [NSData dataWithBytesNoCopy:audioBuffer
											 length:((kCDSectorSizeCDDA * (sectorsRead - readOffsetInSectors)) + readOffsetInBytes)
									   freeWhenDone:NO];

			// Discard any C2 error bits corresponding to discarded samples in the read offset
			zeroTrailingBitsOfBufferInPlace(c2Buffer, (kCDSectorSizeErrorFlags * sectorsRead), readOffsetInFrames);
		}
		else
			audioData = [NSData dataWithBytesNoCopy:audioBuffer 
											 length:(kCDSectorSizeCDDA * sectorsRead) 
									   freeWhenDone:NO];

		// Store the error flags
		[self setErrorFlags:c2Buffer forSectorRange:readRange];
		
		// Write the data to the output file
		UInt32 packetCount = audioData.length / cddaASBD.mBytesPerPacket;
		status = AudioFileWritePackets(file, false, audioData.length, NULL, packetNumber, &packetCount, audioData.bytes);
		if(noErr != status) {
			self.error = [NSError errorWithDomain:NSOSStatusErrorDomain code:status userInfo:nil];
			goto cleanup;
		}
		
		// Update the MD5 and SHA1 digests
		CC_MD5_Update(&md5, audioData.bytes, audioData.length);
		CC_SHA1_Update(&sha1, audioData.bytes, audioData.length);
		
		// Housekeeping
		sectorsRemaining -= sectorsRead;
		packetNumber += packetCount;
		self.fractionComplete = (1.f - (sectorsRemaining / (float)self.sectorsRead.length));
		
		// Stop if requested
		if(self.isCancelled)
			goto cleanup;
	}
	
	// ========================================
	// EXTRACTION PHASE 3: APPEND SILENCE AS NECESSARY

	// Append silence, adjusted for the read offset, if required
	if(sectorsOfSilenceToAppend) {
		memset(buffer, 0, sectorsOfSilenceToAppend * kCDSectorSizeCDDA);
		
		NSData *audioData = [NSData dataWithBytesNoCopy:buffer
												 length:((kCDSectorSizeCDDA * sectorsOfSilenceToAppend) - readOffsetInBytes)
										   freeWhenDone:NO];
		
		// Write the silence to the output file
		UInt32 packetCount = audioData.length / cddaASBD.mBytesPerPacket;
		status = AudioFileWritePackets(file, false, audioData.length, NULL, packetNumber, &packetCount, audioData.bytes);
		if(noErr != status) {
			self.error = [NSError errorWithDomain:NSOSStatusErrorDomain code:status userInfo:nil];
			goto cleanup;
		}

		// Update the MD5 and SHA1 digests
		CC_MD5_Update(&md5, audioData.bytes, audioData.length);
		CC_SHA1_Update(&sha1, audioData.bytes, audioData.length);

		// Housekeeping
		packetNumber += packetCount;
	}

	// ========================================
	// COMPLETE EXTRACTION
	
	self.fractionComplete = 1;

	// Complete the MD5 and SHA1 calculations and store the result
	unsigned char md5Digest [CC_MD5_DIGEST_LENGTH];
	CC_MD5_Final(md5Digest, &md5);

	unsigned char sha1Digest [CC_SHA1_DIGEST_LENGTH];
	CC_SHA1_Final(sha1Digest, &sha1);
	
	NSMutableString *tempString = [NSMutableString string];
	
	NSUInteger i;
	for(i = 0; i < CC_MD5_DIGEST_LENGTH; ++i)
		[tempString appendFormat:@"%02x", md5Digest[i]];
	self.MD5 = tempString;

	tempString = [NSMutableString string];
	for(i = 0; i < CC_SHA1_DIGEST_LENGTH; ++i)
		[tempString appendFormat:@"%02x", sha1Digest[i]];
	self.SHA1 = tempString;
	
	// ========================================
	// CLEAN UP

cleanup:
	// Close the device
	if(![drive closeDevice])
		self.error = drive.error;
	
	// Close the output file
	if(file) {
		status = AudioFileClose(file);
		if(noErr != status)
			self.error = [NSError errorWithDomain:NSOSStatusErrorDomain code:status userInfo:nil];
	}
}

@end

@implementation ExtractionOperation (Private)

// Convert C2 errors (1 bit for each data byte in the sector, 294 bytes of error data per sector) to
// C2 block errors- a simple YES/NO value for each sector (the logical OR of all the C2 error bits)
- (void) setErrorFlags:(const uint8_t *)errorFlags forSectorRange:(SectorRange *)range;
{
	NSParameterAssert(NULL != errorFlags);
	NSParameterAssert(nil != range);

	// For easy comparison
	uint8_t zeroErrorFlags [kCDSectorSizeErrorFlags];
	memset(zeroErrorFlags, 0, kCDSectorSizeErrorFlags);
	
	NSUInteger sectorIndex;
	for(sectorIndex = 0; sectorIndex < range.length; ++sectorIndex) {
		const uint8_t *sectorErrorFlags = errorFlags + (kCDSectorSizeErrorFlags * sectorIndex);

		if(memcmp(sectorErrorFlags, zeroErrorFlags, kCDSectorSizeErrorFlags)) {
			NSUInteger sectorNumber = range.firstSector + sectorIndex;

			// Add this sector to the block error flags
			[_blockErrorFlags addIndex:sectorNumber];
			
			// Copy the error bits as well
			NSData *sectorErrorFlagsData = [NSData dataWithBytes:sectorErrorFlags length:kCDSectorSizeErrorFlags];
			[_errorFlags setObject:sectorErrorFlagsData forKey:[NSNumber numberWithUnsignedInteger:sectorNumber]];
		}
	}
}

@end
