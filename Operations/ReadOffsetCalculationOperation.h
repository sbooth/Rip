/*
 *  Copyright (C) 2008 Stephen F. Booth <me@sbooth.org>
 *  All Rights Reserved
 */

#import <Cocoa/Cocoa.h>

// ========================================
// KVC key names for the read offset dictionaries
// ========================================
extern NSString * const		kReadOffsetKey; // NSNumber *, in sample frames
extern NSString * const		kConfidenceLevelKey; // NSNumber *

// ========================================
// An NSOperation subclass which uses AccurateRip data to detect a drive's read offset
// URL is assumed to point to a file containing CDDA audio with 2n sectors
// The 2n sectors must be centered around the six second point in the specified track
// Graphically:
// |---------|----------|
// -n       6 s        +n
// ========================================
@interface ReadOffsetCalculationOperation : NSOperation
{
@private
	NSURL *_URL;
	NSManagedObjectID *_trackDescriptorID;
	NSNumber *_maximumOffsetToCheck;
	
	NSNumber *_fractionComplete;
	
	NSError *_error;
	NSArray *_possibleReadOffsets;
}

// ========================================
// Properties affecting scanning
@property (assign) NSURL * URL;
@property (assign) NSManagedObjectID * trackDescriptorID;
@property (assign) NSNumber * maximumOffsetToCheck; // In sample frames,  should be a multiple of AUDIO_FRAMES_PER_CDDA_SECTOR

// ========================================
// Properties set during calculation
@property (readonly, assign) NSNumber * fractionComplete;

// ========================================
// Properties set after offset calculation is complete (or cancelled)
@property (readonly, assign) NSError * error;
@property (readonly, assign) NSArray * possibleReadOffsets; // NSArray of NSDictionaries, see keys above

@end
