/*
 *  Copyright (C) 2007 Stephen F. Booth <me@sbooth.org>
 *  All Rights Reserved
 */

#import <Cocoa/Cocoa.h>
#include <DiskArbitration/DiskArbitration.h>

// ========================================
// An NSOperation subclass that scans a compact disc for the pregap
// for a specified track
// ========================================
@interface PreGapDetectionOperation : NSOperation
{
	DADiskRef _disk;				// The DADiskRef holding the CD to scan
	NSNumber *_trackNumber;			// The CD will be scanned for the pre-gap of this track number
	NSNumber *_preGap;				// The pre-gap of the desired track, in sectors
	
	NSError *_error;				// Holds the first error (if any) occurring during scanning
}

// ========================================
// Properties affecting scanning
@property (assign) DADiskRef disk;
@property (copy) NSNumber * trackNumber;

// ========================================
// Properties set after scanning is complete (or cancelled)
@property (readonly, copy) NSNumber * preGap;
@property (readonly, copy) NSError * error;

// ========================================
// Initialization
- (id) initWithDADiskRef:(DADiskRef)disk;

@end
