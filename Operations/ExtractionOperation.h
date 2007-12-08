/*
 *  $Id$
 *  Copyright (C) 2007 Stephen F. Booth <me@sbooth.org>
 *  All Rights Reserved
 */

#import <Cocoa/Cocoa.h>
#include <DiskArbitration/DiskArbitration.h>

@class SectorRange, BitArray, SessionDescriptor;

@interface ExtractionOperation : NSOperation
{
	DADiskRef _disk;
	SectorRange *_sectorRange;
	SessionDescriptor *_session;
	NSString *_path;
	NSNumber *_readOffset;
	NSError *_error;
	BitArray *_errors;
	NSString *_md5;
}

@property (assign) DADiskRef disk;
@property (copy) SectorRange * sectorRange;
@property (copy) SessionDescriptor * session;
@property (copy) NSString * path;
@property (copy) NSNumber * readOffset;
@property (readonly, copy) NSError * error;
@property (readonly, copy) BitArray * errors;
@property (readonly, copy) NSString * md5;

- (id) initWithDADiskRef:(DADiskRef)disk;

@end
