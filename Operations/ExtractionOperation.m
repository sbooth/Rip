/*
 *  Copyright (C) 2007 Stephen F. Booth <me@sbooth.org>
 *  All Rights Reserved
 */

#import "ExtractionOperation.h"
#import "SectorRange.h"
#import "MutableSectorRange.h"
#import "SessionDescriptor.h"
#import "BitArray.h"
#import "Drive.h"
#import "CDDAUtilities.h"

#include "md5.h"

#include <IOKit/storage/IOCDTypes.h>
#include <AudioToolbox/ExtendedAudioFile.h>

// Keep reads to approximately 2 MB in size (2352 + 294 bytes are necessary for each sector)
#define BUFFER_SIZE_IN_SECTORS 775u

@interface ExtractionOperation ()
@property (copy) SectorRange * sectorsRead;
@property (copy) NSError * error;
@property (copy) BitArray * errorFlags;
@property (copy) NSString * md5;
@end

@interface ExtractionOperation (Private)
- (void) setErrorFlags:(const int8_t *)errorFlags forSectorRange:(SectorRange *)range;
@end

@implementation ExtractionOperation

@synthesize disk = _disk;
@synthesize sectors = _sectors;
@synthesize sectorsRead = _sectorsRead;
@synthesize session = _session;
@synthesize trackNumber = _trackNumber;
@synthesize error = _error;
@synthesize errorFlags = _errorFlags;
@synthesize path = _path;
@synthesize readOffset = _readOffset;
@synthesize md5 = _md5;

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
	NSAssert(nil != self.path, @"self.path may not be nil");

	// Open the CD media for reading
	Drive *drive = [[Drive alloc] initWithDADiskRef:self.disk];
	if(![drive openDevice]) {
		self.error = drive.error;
		return;
	}

	// Set up the ASBD for CDDA audio
	const AudioStreamBasicDescription cddaASBD = getStreamDescriptionForCDDA();
	
	// Create and open the output file, overwriting if it exists
	ExtAudioFileRef file = NULL;
	OSStatus status = ExtAudioFileCreateWithURL((CFURLRef)[NSURL fileURLWithPath:self.path], kAudioFileWAVEType, &cddaASBD, NULL, kAudioFileFlags_EraseFile, &file);
	if(noErr != status) {
		self.error = [NSError errorWithDomain:NSOSStatusErrorDomain code:status userInfo:nil];
		return;
	}

	// Initialize the MD5
	md5_state_t md5;
	md5_init(&md5);

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
	// In this case readOffsetInSectors will be 2, and the actual read should be from sectors 1 through 12, with the 
	// first 12 frames of sector 1 skipped and the last 12 frames of sector 12 skipped.
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

	// Store the sectors that will actually be read
	self.sectorsRead = [[SectorRange alloc] initWithFirstSector:firstSectorToRead lastSector:lastSectorToRead];

	// Determine the first sector that can be legally read (so as not to over-read the lead in)
	NSUInteger firstPermissibleSector = 0;
	if(self.session)
		firstPermissibleSector = 0;
	
	// Determine the last sector that can be legally read (so as not to over-read the lead out)
	NSUInteger lastPermissibleSector = NSUIntegerMax;
	if(self.session)
		lastPermissibleSector = self.session.leadOut - 1;
	
	// Setup C2 error flag tracking
	self.errorFlags = [[BitArray alloc] initWithBitCount:self.sectorsRead.length];
	
	// The extraction buffers
	__strong int8_t *buffer = NSAllocateCollectable(BUFFER_SIZE_IN_SECTORS * (kCDSectorSizeCDDA + kCDSectorSizeErrorFlags), 0);
	__strong int8_t *audioBuffer = NSAllocateCollectable(BUFFER_SIZE_IN_SECTORS * kCDSectorSizeCDDA, 0);
	__strong int8_t *c2Buffer = NSAllocateCollectable(BUFFER_SIZE_IN_SECTORS * kCDSectorSizeErrorFlags, 0);
	int8_t *alias = NULL;
	
	if(NULL == buffer || NULL == audioBuffer || NULL == c2Buffer) {
		self.error = [NSError errorWithDomain:NSPOSIXErrorDomain code:ENOMEM userInfo:nil];
		goto cleanup;
	}
	
	// Iteratively extract the desired sector range
	NSUInteger sectorsRemaining = self.sectorsRead.length;
	while(0 < sectorsRemaining) {
		// Set up the parameters for this read
		NSUInteger startSector = self.sectorsRead.firstSector + self.sectorsRead.length - sectorsRemaining;
		NSUInteger sectorCount = MIN(BUFFER_SIZE_IN_SECTORS, sectorsRemaining);
		MutableSectorRange *readRange = [MutableSectorRange sectorRangeWithFirstSector:startSector sectorCount:sectorCount];

		// Clamp the read range to the specified session
		NSUInteger sectorsOfSilenceToPrepend = 0;
		if(readRange.firstSector < firstPermissibleSector) {
			sectorsOfSilenceToPrepend = firstPermissibleSector - readRange.firstSector;
			readRange.firstSector = firstPermissibleSector;
			sectorCount -= sectorsOfSilenceToPrepend;
		}
		
		NSUInteger sectorsOfSilenceToAppend = 0;
		if(readRange.lastSector > lastPermissibleSector) {
			sectorsOfSilenceToAppend = readRange.lastSector - lastPermissibleSector;
			readRange.lastSector = lastPermissibleSector;
			sectorCount -= sectorsOfSilenceToAppend;
		}
		
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
		
		// Append silence as necessary and update the read parameters to reflect these virtual sectors
		if(sectorsOfSilenceToPrepend) {
			// First slide the data that was read over to make room for the silence
			memmove(buffer + (sectorsOfSilenceToPrepend * (kCDSectorSizeCDDA + kCDSectorSizeErrorFlags)), buffer, sectorsRead * (kCDSectorSizeCDDA + kCDSectorSizeErrorFlags));
			memset(buffer, 0, sectorsOfSilenceToPrepend * (kCDSectorSizeCDDA + kCDSectorSizeErrorFlags));
			readRange.firstSector = readRange.firstSector - sectorsOfSilenceToPrepend;
			sectorsRead += sectorsOfSilenceToPrepend;
		}

		// Append silence as necessary and update the read parameters to reflect these virtual sectors
		if(sectorsOfSilenceToAppend) {
			memset(buffer + (sectorsRead * (kCDSectorSizeCDDA + kCDSectorSizeErrorFlags)), 0, sectorsOfSilenceToAppend * (kCDSectorSizeCDDA + kCDSectorSizeErrorFlags));
			readRange.lastSector = readRange.lastSector + sectorsOfSilenceToAppend;
			sectorsRead += sectorsOfSilenceToAppend;
		}
		
		// Copy the audio and C2 data to their respective buffers
		NSUInteger i;
		for(i = 0; i < sectorsRead; ++i) {
			alias = buffer + (i * (kCDSectorSizeCDDA + kCDSectorSizeErrorFlags));
			
			memcpy(audioBuffer + (i * kCDSectorSizeCDDA), alias, kCDSectorSizeCDDA);
			memcpy(c2Buffer + (i * kCDSectorSizeErrorFlags), alias + kCDSectorSizeCDDA, kCDSectorSizeErrorFlags);				
			//memcpy(qBuffer + (i * kCDSectorSizeQSubchannel), alias + kCDSectorSizeCDDA + kCDSectorSizeErrorFlags, kCDSectorSizeQSubchannel);
		}

		// Store the error flags
		[self setErrorFlags:c2Buffer forSectorRange:readRange];

		NSData *audioData = nil;
		
		// Adjust the data read for the read offset
		if(readRange.firstSector == self.sectorsRead.firstSector)
			audioData = [NSData dataWithBytesNoCopy:(audioBuffer + readOffsetInBytes)
											 length:((kCDSectorSizeCDDA * sectorsRead) - readOffsetInBytes)
									   freeWhenDone:NO];
		else if(readRange.lastSector == self.sectorsRead.lastSector)
			audioData = [NSData dataWithBytesNoCopy:audioBuffer
											 length:((kCDSectorSizeCDDA * (sectorsRead - readOffsetInSectors)) + readOffsetInBytes)
									   freeWhenDone:NO];
		else
			audioData = [NSData dataWithBytesNoCopy:audioBuffer 
											 length:(kCDSectorSizeCDDA * sectorsRead) 
									   freeWhenDone:NO];

		// Stuff the data in an AudioBufferList
		AudioBufferList audioBuffer;
		audioBuffer.mNumberBuffers = 1;
		audioBuffer.mBuffers[0].mNumberChannels = cddaASBD.mChannelsPerFrame;
		audioBuffer.mBuffers[0].mData = (void *)audioData.bytes;
		audioBuffer.mBuffers[0].mDataByteSize = audioData.length;
		
		// Write the data to the output file
		status = ExtAudioFileWrite(file, (audioData.length / cddaASBD.mBytesPerFrame), &audioBuffer);
		if(noErr != status) {
			self.error = [NSError errorWithDomain:NSOSStatusErrorDomain code:status userInfo:nil];
			goto cleanup;
		}
		
		// Update the MD5 digest
		md5_append(&md5, audioData.bytes, audioData.length);
		
		// Housekeeping
		sectorsRemaining -= sectorsRead;
		
		// Stop if requested
		if(self.isCancelled)
			goto cleanup;
	}
	
	// Complete the MD5 calculation and store the result
	md5_byte_t digest [16];
	md5_finish(&md5, digest);
	
	self.md5 = [NSString stringWithFormat:@"%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x", digest[0], digest[1], digest[2], digest[3], digest[4], digest[5], digest[6], digest[7], digest[8], digest[9], digest[10], digest[11], digest[12], digest[13], digest[14], digest[15]];

cleanup:
	// Close the device
	if(![drive closeDevice])
		self.error = drive.error;
	
	// Close the output file
	status = ExtAudioFileDispose(file);
	if(noErr != status)
		self.error = [NSError errorWithDomain:NSOSStatusErrorDomain code:status userInfo:nil];
}

@end

@implementation ExtractionOperation (Private)

// range will always be a subset of self.sectorsRead
- (void) setErrorFlags:(const int8_t *)errorFlags forSectorRange:(SectorRange *)range
{
	NSParameterAssert(NULL != errorFlags);
	NSParameterAssert(nil != range);
	
	NSUInteger i, j;
	for(i = 0; i < kCDSectorSizeErrorFlags * range.length; ++i) {
		if(errorFlags[i]) {
			for(j = 0; j < 8; ++j) {
				if((1 << j) & errorFlags[i])
					[_errorFlags setValue:YES forIndex:(range.firstSector - self.sectorsRead.firstSector + ((8 * i) + j))];
			}					
		}
	}
}

@end
