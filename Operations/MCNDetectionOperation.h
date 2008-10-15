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
	__strong DADiskRef _disk;			// The DADiskRef holding the CD to scan	
	NSError *_error;					// Holds the first error (if any) occurring during scanning
}

// ========================================
// Properties affecting scanning
@property (assign) DADiskRef disk;

// ========================================
// Properties set after scanning is complete (or cancelled)
@property (readonly, copy) NSError * error;

// ========================================
// Initialization
- (id) initWithDADiskRef:(DADiskRef)disk;

@end
