/*
 *  Copyright (C) 2008 Stephen F. Booth <me@sbooth.org>
 *  All Rights Reserved
 */

#import <Cocoa/Cocoa.h>

@interface ReadOffsetCalculationOperation : NSOperation
{
	@private
	NSURL *_URL;
	NSManagedObjectID *_trackDescriptorID;
	NSNumber *_trackFirstSectorOffset;
	NSNumber *_maximumOffsetToCheck;
	NSError *_error;
	NSNumber *_readOffset;
}

// ========================================
// Properties affecting scanning
@property (assign) NSURL * URL;
@property (assign) NSManagedObjectID * trackDescriptorID; // Should NOT be the first or last track on the disc
@property (assign) NSNumber * trackFirstSectorOffset; // In URL
@property (assign) NSNumber * maximumOffsetToCheck; // In sample frames,  should be a multiple of AUDIO_FRAMES_PER_CDDA_SECTOR

// ========================================
// Properties set after offset calculation is complete (or cancelled)
@property (readonly, assign) NSError * error;
@property (readonly, assign) NSNumber * readOffset; // In sample frames

@end
