/*
 *  $Id$
 *  Copyright (C) 2007 Stephen F. Booth <me@sbooth.org>
 *  All Rights Reserved
 */

#import "ExtractionOperation.h"
#import "SectorRange.h"
#import "BitArray.h"
#import "Drive.h"

#include <IOKit/storage/IOCDTypes.h>

// Keep reads to approximately 2 MB in size (2352 + 294 bytes are necessary for each sector)
#define BUFFER_SIZE_IN_SECTORS 775u

@interface ExtractionOperation ()
@property (copy) NSError * error;
@property (copy) BitArray * errors;
@end

@interface ExtractionOperation (Private)
- (void) setErrorFlags:(const int8_t *)errorFlags forSectorRange:(SectorRange *)range;
@end

@implementation ExtractionOperation

@synthesize disk = _disk;
@synthesize sectorRange = _sectorRange;
@synthesize error = _error;
@synthesize errors = _errors;
@synthesize path = _path;
@synthesize readOffset = _readOffset;

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

	NSError *error = nil;
	if(![drive openDevice:&error]) {
		self.error = error;
		return;
	}

	NSInteger readOffsetInFrames = 0;
	NSNumber *readOffset = self.readOffset;
	if(readOffset)
		readOffsetInFrames = readOffset.integerValue;

	// Handle positive read offsets
	if(0 < readOffsetInFrames) {
		NSUInteger readOffsetInBytes = 2 * sizeof(int16_t) * readOffsetInFrames;
		NSUInteger readOffsetInSectors = (readOffsetInFrames +  587) / 588;

		// Adjust the range of sectors that will be extracted when the read offset is taken into account
		if(1 < readOffsetInSectors)
			self.sectorRange.firstSector = (self.sectorRange.firstSector + readOffsetInSectors);
		self.sectorRange.lastSector = (self.sectorRange.lastSector + readOffsetInSectors);

		// Setup C2 error flag tracking
		self.errors = [[BitArray alloc] init];
		self.errors.bitCount = self.sectorRange.length;
		
		// The extraction buffers
		int8_t *buffer = NSAllocateCollectable(BUFFER_SIZE_IN_SECTORS * (kCDSectorSizeCDDA + kCDSectorSizeErrorFlags), 0);
		int8_t *audioBuffer = NSAllocateCollectable(BUFFER_SIZE_IN_SECTORS * kCDSectorSizeCDDA, 0);
		int8_t *c2Buffer = NSAllocateCollectable(BUFFER_SIZE_IN_SECTORS * kCDSectorSizeErrorFlags, 0);
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
			
			// Read from the CD media
			NSUInteger sectorsRead = [drive readAudioAndErrorFlags:buffer sectorRange:readRange];
			
			// Verify the requested sectors were read
			if(sectorsRead != sectorCount) {
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
			
			// Housekeeping
			sectorsRemaining -= sectorsRead;
			
			// Stop if requested
			if(self.isCancelled)
				goto cleanup;
		}
	}
	// Handle negative read offsets
	else {
//		NSInteger readOffsetInSectors = (readOffsetInFrames - 587) / 588;		
		NSLog(@"Negative read offset of %i frames", readOffsetInFrames);
	}
	
	NSLog(@"%u C2 errors during extraction", self.errors.countOfOnes);
	
cleanup:
	// Close the device
	if(![drive closeDevice:&error])
		self.error = error;
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
					[self.errors setValue:YES forIndex:(range.firstSector + ((8 * i) + j))];
			}					
		}
	}
}

@end
