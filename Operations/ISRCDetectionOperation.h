/*
 *  Copyright (C) 2008 Stephen F. Booth <me@sbooth.org>
 *  All Rights Reserved
 */

#import <Cocoa/Cocoa.h>
#include <DiskArbitration/DiskArbitration.h>

// ========================================
// An NSOperation subclass that gets the ISRC for a track from a compact disc, if present
// ========================================
@interface ISRCDetectionOperation : NSOperation
{
@private
	DADiskRef _disk;				// The DADiskRef holding the CD to scan
	NSManagedObjectID *_trackID;	// The track to be scanned
	
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
