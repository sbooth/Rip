/*
 *  Copyright (C) 2007 Stephen F. Booth <me@sbooth.org>
 *  All Rights Reserved
 */

#import <Cocoa/Cocoa.h>
#include <DiskArbitration/DiskArbitration.h>

@class SectorRange, BitArray;

// ========================================
// An NSOperation subclass that extracts audio from a specified range of sectors
// on a compact disc, adjusting for a read offset and optionally limiting extraction
// to a specific range of sectors (typically a session).
// ========================================
@interface ExtractionOperation : NSOperation
{
@private
	DADiskRef _disk;				// The DADiskRef holding the CD from which to extract
	SectorRange *_sectors;			// The sectors to be extracted (not adjusted for read offset) 
	SectorRange *_allowedSectors;	// The range of sectors to which extraction will be limited
	NSURL *_URL;					// The URL of the output file
	NSNumber *_readOffset;			// The read offset (in audio frames) to use for extraction
	NSArray *_trackIDs;				// The CD track(s) being extracted (if applicable)
	
	SectorRange *_sectorsRead;		// The sectors that were actually read (sectors adjusted for read offset)
	NSError *_error;				// Holds the first error (if any) occurring during extraction
	BitArray *_errorFlags;			// C2 error flags corresponding to readSectors
	NSString *_MD5;					// The MD5 sum of the extracted audio
}

// ========================================
// Properties affecting extraction
@property (assign) DADiskRef disk;
@property (assign) SectorRange * sectors;
@property (assign) SectorRange * allowedSectors;
@property (assign) NSURL * URL;
@property (assign) NSNumber * readOffset;
@property (assign) NSArray * trackIDs;

// ========================================
// Properties set after extraction is complete (or cancelled)
@property (readonly, assign) SectorRange * sectorsRead;
@property (readonly, assign) NSError * error;
@property (readonly, assign) BitArray * errorFlags;
@property (readonly, assign) NSString * MD5;

// ========================================
// Initialization
- (id) initWithDADiskRef:(DADiskRef)disk;

@end
