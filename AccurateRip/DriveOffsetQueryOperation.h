/*
 *  Copyright (C) 2008 - 2009 Stephen F. Booth <me@sbooth.org>
 *  All Rights Reserved
 */

#import <Cocoa/Cocoa.h>
#include <DiskArbitration/DiskArbitration.h>

// ========================================
// An NSOperation subclass that downloads the AccurateRip drive offsets 
// database and searches it for a specific drive
// ========================================
@interface DriveOffsetQueryOperation : NSOperation
{
@private
	DADiskRef _disk;
	NSNumber *_readOffset;
	NSError *_error;
}

// ========================================
// Properties affecting the query
@property (assign) DADiskRef disk;

// ========================================
// Properties set after the query is complete (or cancelled)
@property (readonly, copy) NSNumber * readOffset;
@property (readonly, copy) NSError * error;

@end
