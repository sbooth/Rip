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
extern NSString * const		kAccurateRipTrackIDKey; // NSManagedObjectID * for an AccurateRipTrackDescriptor *

// ========================================
// An NSOperation subclass which uses AccurateRip data to detect extracted audio's read offset
// URL is assumed to point to a file containing CDDA audio with the six second
// point of the track to check occurring at sixSecondPoint
// Offsets ranging from  -maximumOffsetToCheck to +maximumOffsetToCheck will be
// checked
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
	NSUInteger _sixSecondPointSector;
	NSUInteger _maximumOffsetToCheck;
	
	float _fractionComplete;
	
	NSError *_error;
	NSArray *_possibleReadOffsets;
}

// ========================================
// Properties affecting scanning
@property (assign) NSURL * URL;
@property (assign) NSManagedObjectID * trackDescriptorID;
@property (assign) NSUInteger sixSecondPointSector; // In CDDA sectors
@property (assign) NSUInteger maximumOffsetToCheck; // In sample frames,  should be a multiple of AUDIO_FRAMES_PER_CDDA_SECTOR

// ========================================
// Properties set during calculation
@property (readonly, assign) float fractionComplete;

// ========================================
// Properties set after offset calculation is complete (or cancelled)
@property (readonly, assign) NSError * error;
@property (readonly, assign) NSArray * possibleReadOffsets; // NSArray of NSDictionaries, see keys above

@end
