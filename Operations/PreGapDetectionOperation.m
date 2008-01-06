/*
 *  Copyright (C) 2007 Stephen F. Booth <me@sbooth.org>
 *  All Rights Reserved
 */

#import "PreGapDetectionOperation.h"
#import "SectorRange.h"
#import "Drive.h"
#import "CompactDisc.h"

// The typical pregap is 2 seconds, or 150 sectors
#define BUFFER_SIZE_IN_SECTORS 150u

#pragma pack(push, 1)                        /* (enable 8-bit struct packing) */

// ========================================
// Q subchannel data format
// ========================================
struct QSubChannelData {
#ifdef __LITTLE_ENDIAN__
	UInt8 adr:4;
	UInt8 control:4;
#else /* !__LITTLE_ENDIAN__ */
	UInt8 control:4;
	UInt8 adr:4;
#endif /* !__LITTLE_ENDIAN__ */
	UInt8 tno;
	UInt8 index;
	CDMSF msf;
	UInt8 zero;
	CDMSF amsf;
	UInt16 crc;
	UInt16 pad;
	UInt8 pad2;
#ifdef __LITTLE_ENDIAN__
	UInt8 zero2:7;
	UInt8 p:1;
#else /* !__LITTLE_ENDIAN__ */
	UInt8 p:1;
	UInt8 zero2:7;
#endif /* !__LITTLE_ENDIAN__ */
};

#pragma pack(pop)                        /* (reset to default struct packing) */

// ========================================
// Utility functions for dealing with BCD values
// ========================================
static UInt8
convertBCDToDecimal(UInt8 bcdValue)
{
	UInt8 highNibble = 0x0F & (bcdValue >> 4);
	UInt8 lowNibble = 0x0F & bcdValue;
	
	return (10 * highNibble) + lowNibble;
}

static void
convertQSubChannelDataFromBCDToDecimal(struct QSubChannelData *qData)
{
	NSCParameterAssert(NULL != qData);
	
	// Convert BCD to decimal representation
	qData->tno = convertBCDToDecimal(qData->tno);
	qData->index = convertBCDToDecimal(qData->index);
	qData->msf.minute = convertBCDToDecimal(qData->msf.minute);
	qData->msf.second = convertBCDToDecimal(qData->msf.second);
	qData->msf.frame = convertBCDToDecimal(qData->msf.frame);
	qData->amsf.minute = convertBCDToDecimal(qData->amsf.minute);
	qData->amsf.second = convertBCDToDecimal(qData->amsf.second);
	qData->amsf.frame = convertBCDToDecimal(qData->amsf.frame);
}

@interface PreGapDetectionOperation ()
@property (copy) NSNumber * preGap;
@property (copy) NSError * error;
@end

@implementation PreGapDetectionOperation

@synthesize disk = _disk;
@synthesize trackNumber = _trackNumber;
@synthesize preGap = _preGap;
@synthesize error = _error;

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
	NSAssert(nil != self.trackNumber, @"self.trackNumber may not be nil");

	// For the first track, the pre-gap is the area between the sector 0 and the track's first sector
	if(1 == self.trackNumber.unsignedIntegerValue) {
		CompactDisc *compactDisc = [[CompactDisc alloc] initWithDADiskRef:self.disk];

		if(0 != [compactDisc firstSectorForTrack:1])
		   self.preGap = [NSNumber numberWithUnsignedInteger:[compactDisc firstSectorForTrack:1]];
		else
			self.preGap = [NSNumber numberWithUnsignedInteger:150];
		   
		return;
	}

	// ========================================
	// GENERAL SETUP
	
	// Open the CD media for reading
	Drive *drive = [[Drive alloc] initWithDADiskRef:self.disk];
	if(![drive openDevice]) {
		self.error = drive.error;
		return;
	}
	
	// Allocate the extraction buffers
	__strong int8_t *buffer = NSAllocateCollectable(BUFFER_SIZE_IN_SECTORS * (kCDSectorSizeCDDA + kCDSectorSizeQSubchannel), 0);
	__strong int8_t *qBuffer = NSAllocateCollectable(BUFFER_SIZE_IN_SECTORS * kCDSectorSizeQSubchannel, 0);
	int8_t *alias = NULL;
	struct QSubChannelData *qData = NULL;

	if(NULL == buffer || NULL == qBuffer) {
		self.error = [NSError errorWithDomain:NSPOSIXErrorDomain code:ENOMEM userInfo:nil];
		goto cleanup;
	}
	
	CompactDisc *compactDisc = [[CompactDisc alloc] initWithDADiskRef:self.disk];
	
	// Store the sector range delineating the track holding the pregap
	NSUInteger trackToScan = self.trackNumber.unsignedIntegerValue - 1;
	NSUInteger firstSector = [compactDisc firstSectorForTrack:trackToScan];
	NSUInteger lastSector = [compactDisc lastSectorForTrack:trackToScan];
		
	// ========================================
	// ITERATIVELY EXTRACT AND SCAN MODE-1 Q

	// Since the pregap for a track is located at the end of the preceding track, perform a backwards search
	NSUInteger startSector = lastSector;
	NSUInteger preGapStart = 0;
	
	NSUInteger sectorsRemaining = lastSector - firstSector + 1;
	while(0 < sectorsRemaining) {
		NSUInteger sectorCount = MIN(BUFFER_SIZE_IN_SECTORS, sectorsRemaining);
		
		SectorRange *readRange = [SectorRange sectorRangeWithLastSector:startSector sectorCount:sectorCount];
		NSUInteger sectorsRead = [drive readAudioAndQSubchannel:buffer sectorRange:readRange];
		
		// Verify the requested sectors were read
		if(0 == sectorsRead) {
			self.error = drive.error;
			goto cleanup;
		}
		else if(sectorsRead != sectorCount) {
			self.error = [NSError errorWithDomain:NSPOSIXErrorDomain code:EIO userInfo:nil];
			goto cleanup;
		}
		
		// Copy the q data to its buffer and convert from BCD representation to decimal
		NSUInteger i;
		for(i = 0; i < sectorsRead; ++i) {
			alias = buffer + (i * (kCDSectorSizeCDDA + kCDSectorSizeQSubchannel));
			
			// Convert from BCD to decimal representation
			convertQSubChannelDataFromBCDToDecimal((struct QSubChannelData *)(alias + kCDSectorSizeCDDA));
			
			memcpy(qBuffer + (i * kCDSectorSizeQSubchannel), alias + kCDSectorSizeCDDA, kCDSectorSizeQSubchannel);
		}
		
		// Loop through the Mode-1 Q and look for the start of the pregap
		for(i = 0; i < sectorsRead; ++i) {
			qData = (struct QSubChannelData *)(qBuffer + (i * kCDSectorSizeQSubchannel));
			
			// Ignore everything except Mode-1 Q in the program area (AKA current position Q)
			if(0x1 != qData->adr)
				continue;
			
			// Sanity check
			if(0 != qData->zero) {
#if DEBUG
				NSLog(@"Mode-1 Q error: 8 bits of zero missing for sector %i", readRange.firstSector + i);
#endif
				continue;
			}
			
			// The pregap is encoded as index 0 with the subsequent track number
			if(1 + trackToScan == qData->tno && 0 == qData->index) {
				preGapStart = readRange.firstSector + i;
				break;
			}
		}
		
		// If no pregap was found, stop looking since this is a backwards search
		if(0 == preGapStart)
			break;
		// If the pregap was found, ensure that the entirety was accounted for
		else if(preGapStart != readRange.firstSector)
			break;
		
		// Housekeeping
		sectorsRemaining -= sectorsRead;
		startSector -= sectorsRead;

		// Stop if requested
		if(self.isCancelled)
			goto cleanup;
	}

	if(0 != preGapStart)
		self.preGap = [NSNumber numberWithUnsignedInteger:(lastSector - preGapStart + 1)];
	
	// ========================================
	// CLEAN UP
	
cleanup:
	// Close the device
	if(![drive closeDevice])
		self.error = drive.error;	
}

@end