/*
 *  Copyright (C) 2007 Stephen F. Booth <me@sbooth.org>
 *  All Rights Reserved
 */

#import <Cocoa/Cocoa.h>
#include <DiskArbitration/DiskArbitration.h>

@class SectorRange, BitArray, SessionDescriptor;

// ========================================
// An NSOperation subclass that extracts audio from a specified range of sectors
// on a compact disc, adjusting for a read offset and limiting extraction
// to a specific session on the disc.
// ========================================
@interface ExtractionOperation : NSOperation
{
	DADiskRef _disk;				// The DADiskRef holding the CD from which to extract
	SectorRange *_sectors;			// The sectors to be extracted (not adjusted for read offset) 
	NSString *_path;				// The pathname of the output file
	NSNumber *_readOffset;			// The read offset (in audio frames) to use for extraction
	SessionDescriptor *_session;	// The CD session that will limit extraction
	NSNumber *_trackNumber;			// The CD track number (if applicable)
	
	SectorRange *_sectorsRead;		// The sectors that were actually read (sectors adjusted for read offset)
	NSError *_error;				// Holds the first error (if any) occurring during extraction
	BitArray *_errorFlags;			// C2 error flags corresponding to readSectors
	NSString *_md5;					// The MD5 sum of the extracted audio
}

// ========================================
// Properties affecting extraction
@property (assign) DADiskRef disk;
@property (copy) SectorRange * sectors;
@property (copy) NSString * path;
@property (copy) NSNumber * readOffset;
@property (copy) SessionDescriptor * session;
@property (copy) NSNumber * trackNumber;

// ========================================
// Properties set after extraction is complete (or cancelled)
@property (readonly, copy) SectorRange * sectorsRead;
@property (readonly, copy) NSError * error;
@property (readonly, copy) BitArray * errorFlags;
@property (readonly, copy) NSString * md5;

// ========================================
// Initialization
- (id) initWithDADiskRef:(DADiskRef)disk;

@end
