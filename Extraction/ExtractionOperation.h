/*
 *  Copyright (C) 2007 - 2008 Stephen F. Booth <me@sbooth.org>
 *  All Rights Reserved
 */

#import <Cocoa/Cocoa.h>
#include <DiskArbitration/DiskArbitration.h>

@class SectorRange;

// ========================================
// An NSOperation subclass that extracts audio from a specified range of sectors
// on a compact disc, adjusting for a read offset and optionally limiting extraction
// to a specific range of sectors (typically a session).
// ========================================
@interface ExtractionOperation : NSOperation
{
@private
	__strong DADiskRef _disk;		// The DADiskRef holding the CD from which to extract
	SectorRange *_sectors;			// The sectors to be extracted (not adjusted for read offset) 
	SectorRange *_allowedSectors;	// The range of sectors to which extraction will be limited
	NSUInteger _cushionSectors;		// Cushion (buffer) sectors to extract on either side
	NSURL *_URL;					// The URL of the output file
	NSNumber *_readOffset;			// The read offset (in audio frames) to use for extraction
	NSManagedObjectID *_trackID;	// The CD track the sectors being extracted belong to
	
	NSDate *_startTime;				// The time the operation started
	float _fractionComplete;		// A float [0, 1] indicating the extraction progress
	
	SectorRange *_sectorsRead;		// The sectors that were actually read (sectors adjusted for read offset)
	NSError *_error;				// Holds the first error (if any) occurring during extraction
	NSString *_MD5;					// The MD5 sum of the extracted audio (not including cushion sectors)
	NSString *_fullMD5;				// The MD5 sum of the extracted audio (including cushion sectors)
	NSString *_SHA1;				// The SHA1 sum of the extracted audio (not including cushion sectors)
	NSString *_fullSHA1;			// The SHA1 sum of the extracted audio (including cushion sectors)

	BOOL _useC2;							// Whether to request C2 error information
	NSMutableIndexSet *_blockErrorFlags;	// C2 block error flags (indexes correspond to disc sectors)
	NSMutableDictionary *_errorFlags;		// NSNumber * keys correspond to disc sectors, NSData * values
}

// ========================================
// Properties affecting extraction
@property (assign) DADiskRef disk;
@property (copy) SectorRange * sectors;
@property (copy) SectorRange * allowedSectors;
@property (assign) NSUInteger cushionSectors;
@property (copy) NSURL * URL;
@property (copy) NSNumber * readOffset;
@property (copy) NSManagedObjectID * trackID;
@property (assign) BOOL useC2;

// ========================================
// Properties set during extraction
@property (readonly, assign) NSDate * startTime;
@property (readonly, assign) float fractionComplete;

// ========================================
// Properties set after extraction is complete (or cancelled)
@property (readonly, copy) SectorRange * sectorsRead;
@property (readonly, copy) NSError * error;
@property (readonly, copy) NSIndexSet * blockErrorFlags;
@property (readonly, copy) NSDictionary * errorFlags;
@property (readonly, copy) NSString * MD5;
@property (readonly, copy) NSString * fullMD5;
@property (readonly, copy) NSString * SHA1;
@property (readonly, copy) NSString * fullSHA1;

// ========================================
// Initialization
- (id) initWithDADiskRef:(DADiskRef)disk;

@end
