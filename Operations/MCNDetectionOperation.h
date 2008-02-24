/*
 *  Copyright (C) 2008 Stephen F. Booth <me@sbooth.org>
 *  All Rights Reserved
 */

#import <Cocoa/Cocoa.h>
#include <DiskArbitration/DiskArbitration.h>

// ========================================
// An NSOperation subclass that reads the MCN from a compact disc
// ========================================
@interface MCNDetectionOperation : NSOperation
{
@private
	DADiskRef _disk;				// The DADiskRef holding the CD to scan
	NSManagedObjectID *_compactDiscID;	// The CD to be scanned
	
	NSError *_error;				// Holds the first error (if any) occurring during scanning
}

// ========================================
// Properties affecting scanning
@property (assign) DADiskRef disk;
@property (assign) NSManagedObjectID * compactDiscID;

// ========================================
// Properties set after scanning is complete (or cancelled)
@property (readonly, assign) NSError * error;

// ========================================
// Initialization
- (id) initWithDADiskRef:(DADiskRef)disk;

@end
