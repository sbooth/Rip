/*
 *  Copyright (C) 2007 - 2008 Stephen F. Booth <me@sbooth.org>
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
@private
	DADiskRef _disk;				// The DADiskRef holding the CD to scan
	NSManagedObjectID *_trackID;	// The CD will be scanned for the pre-gap of this track
	
	NSError *_error;				// Holds the first error (if any) occurring during scanning
}

// ========================================
// Properties affecting scanning
@property (assign) DADiskRef disk;
@property (assign) NSManagedObjectID * trackID;

// ========================================
// Properties set after scanning is complete (or cancelled)
@property (readonly, assign) NSError * error;

// ========================================
// Initialization
- (id) initWithDADiskRef:(DADiskRef)disk;

@end
