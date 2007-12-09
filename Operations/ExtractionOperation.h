/*
 *  Copyright (C) 2007 Stephen F. Booth <me@sbooth.org>
 *  All Rights Reserved
 */

#import <Cocoa/Cocoa.h>
#include <DiskArbitration/DiskArbitration.h>

@class SectorRange, BitArray, SessionDescriptor;

// ========================================
// An NSOperation subclass that extracts audio from a specified range of sectors
// on a CD, adjusting for a read offset
// ========================================
@interface ExtractionOperation : NSOperation
{
	DADiskRef _disk;
	SectorRange *_sectorRange;
	NSString *_path;
	NSNumber *_readOffset;
	SessionDescriptor *_session;
	NSNumber *_trackNumber;
	
	NSError *_error;
	BitArray *_errorFlags;
	NSString *_md5;
}

// ========================================
// Properties affecting extraction
@property (assign) DADiskRef disk;
@property (copy) SectorRange * sectorRange;
@property (copy) NSString * path;
@property (copy) NSNumber * readOffset;
@property (copy) SessionDescriptor * session;
@property (copy) NSNumber * trackNumber;

// ========================================
// Properties set after extraction is complete (or cancelled)
@property (readonly, copy) NSError * error;
@property (readonly, copy) BitArray * errorFlags;
@property (readonly, copy) NSString * md5;

- (id) initWithDADiskRef:(DADiskRef)disk;

@end
