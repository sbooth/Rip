/*
 *  $Id$
 *  Copyright (C) 2007 Stephen F. Booth <me@sbooth.org>
 *  All Rights Reserved
 */

#import "ExtractionOperation.h"
#import "SectorRange.h"
#import "SessionDescriptor.h"
#import "BitArray.h"
#import "Drive.h"

#include "md5.h"

#include <IOKit/storage/IOCDTypes.h>

// Keep reads to approximately 2 MB in size (2352 + 294 bytes are necessary for each sector)
#define BUFFER_SIZE_IN_SECTORS 775u

@interface ExtractionOperation ()
@property (copy) NSError * error;
@property (copy) BitArray * errorFlags;
@property (copy) NSString * md5;
@end

@interface ExtractionOperation (Private)
- (void) setErrorFlags:(const int8_t *)errorFlags forSectorRange:(SectorRange *)range;
@end

@implementation ExtractionOperation

@synthesize disk = _disk;
@synthesize sectorRange = _sectorRange;
@synthesize session = _session;
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
	NSAssert(nil != self.sectorRange, @"self.sectorRange may not be nil");
	NSAssert(nil != self.path, @"self.path may not be nil");

	// Create the output file if it doesn't exists
	if(![[NSFileManager defaultManager] fileExistsAtPath:self.path] && ![[NSFileManager defaultManager] createFileAtPath:self.path contents:nil attributes:nil]) {
		self.error = [NSError errorWithDomain:NSPOSIXErrorDomain code:ENOENT userInfo:nil];
		return;
	}
	
	Drive *drive = [[Drive alloc] initWithDADiskRef:self.disk];
	NSFileHandle *fileHandle = [NSFileHandle fileHandleForWritingAtPath:self.path];
	
	if(nil == fileHandle) {
		self.error = [NSError errorWithDomain:NSPOSIXErrorDomain code:ENOENT userInfo:nil];
		return;
	}

	if(![drive openDevice]) {
		self.error = drive.error;
		return;
	}

	// Initialize the MD5
	md5_state_t md5;
	md5_init(&md5);

	NSInteger readOffsetInFrames = 0;
	NSNumber *readOffset = self.readOffset;
	if(readOffset)
		readOffsetInFrames = readOffset.integerValue;

	// ========================================
	// Handle positive/zero read offsets
	if(0 <= readOffsetInFrames) {
		// readOffsetInSectors is the additional number of sectors that must be extracted (at the end) to ensure a 
		// complete sector will exist when the beginning of the read is adjusted by the read offset.
		// If this value is larger than one sector, one sector less than this should be skipped at the beginning.
		// For example, suppose the desired range is sectors 1 through 10 and the read offset is 600 frames.
		// In this case readOffsetInSectors will be 2, and the actual read should be from sectors 1 through 12, with the 
		// first 12 frames of sector 1 skipped and the last 12 frames of sector 12 skipped.
		NSUInteger readOffsetInSectors = (readOffsetInFrames +  587) / 588;
		NSUInteger readOffsetInBytes = 2 * sizeof(int16_t) * readOffsetInFrames;

		// Adjust the range of sectors that will be extracted when the read offset is taken into account
		if(1 < readOffsetInSectors) {
			self.sectorRange.firstSector = (self.sectorRange.firstSector + readOffsetInSectors - 1);
			
			// Skipped whole sectors are taken into account above, so subtract them out here
			while(kCDSectorSizeCDDA > readOffsetInBytes)
				readOffsetInBytes -= kCDSectorSizeCDDA;
		}
		self.sectorRange.lastSector = (self.sectorRange.lastSector + readOffsetInSectors);

		// Determine the last sector that can be legally read (so as not to over-read the lead out)
		NSUInteger lastPermissibleSector = NSUIntegerMax;
		if(self.session)
			lastPermissibleSector = self.session.leadOut - 1;
		
		// Setup C2 error flag tracking
		self.errorFlags = [[BitArray alloc] initWithBitCount:self.sectorRange.length];
		
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
		NSUInteger sectorsRemaining = self.sectorRange.length;
		while(0 < sectorsRemaining) {
			// Set up the parameters for this read
			NSUInteger startSector = self.sectorRange.firstSector + self.sectorRange.length - sectorsRemaining;
			NSUInteger sectorCount = MIN(BUFFER_SIZE_IN_SECTORS, sectorsRemaining);
			SectorRange *readRange = [SectorRange sectorRangeWithFirstSector:startSector sectorCount:sectorCount];
			
			// Clamp the read range to the specified session
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
			
			// Adjust reads for the read offset
			if(readRange.firstSector == self.sectorRange.firstSector)
				audioData = [NSData dataWithBytesNoCopy:(audioBuffer + readOffsetInBytes)
												 length:((kCDSectorSizeCDDA * sectorsRead) - readOffsetInBytes)
										   freeWhenDone:NO];
			else if(readRange.lastSector == self.sectorRange.lastSector)
				audioData = [NSData dataWithBytesNoCopy:audioBuffer
												 length:((kCDSectorSizeCDDA * (sectorsRead - readOffsetInSectors)) + readOffsetInBytes)
										   freeWhenDone:NO];
			else
				audioData = [NSData dataWithBytesNoCopy:audioBuffer 
												 length:(kCDSectorSizeCDDA * sectorsRead) 
										   freeWhenDone:NO];
			
			// Write the data to the output file
			[fileHandle writeData:audioData];
			
			// Update the MD5 digest
			md5_append(&md5, audioData.bytes, audioData.length);
			
			// Housekeeping
			sectorsRemaining -= sectorsRead;
			
			// Stop if requested
			if(self.isCancelled)
				goto cleanup;
		}
	}
	// ========================================
	// Handle negative read offsets
	else {
//		NSInteger readOffsetInSectors = (readOffsetInFrames - 587) / 588;		
		NSLog(@"Negative read offset of %i frames", readOffsetInFrames);
	}
	
	// Complete the MD5 calculation and store the result
	md5_byte_t digest [16];
	md5_finish(&md5, digest);
	
	self.md5 = [NSString stringWithFormat:@"%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x", digest[0], digest[1], digest[2], digest[3], digest[4], digest[5], digest[6], digest[7], digest[8], digest[9], digest[10], digest[11], digest[12], digest[13], digest[14], digest[15]];

cleanup:
	// Close the device
	if(![drive closeDevice])
		self.error = drive.error;
}

@end

@implementation ExtractionOperation (Private)

- (void) setErrorFlags:(const int8_t *)errorFlags forSectorRange:(SectorRange *)range
{
	NSParameterAssert(NULL != errorFlags);
	NSParameterAssert(nil != range);
	
	NSUInteger i, j;
	for(i = 0; i < kCDSectorSizeErrorFlags * range.length; ++i) {
		if(errorFlags[i]) {
			for(j = 0; j < 8; ++j) {
				if((1 << j) & errorFlags[i])
					[_errorFlags setValue:YES forIndex:(range.firstSector + ((8 * i) + j))];
			}					
		}
	}
}

@end
