/*
 *  Copyright (C) 2007 - 2008 Stephen F. Booth <me@sbooth.org>
 *  All Rights Reserved
 */

#import <Cocoa/Cocoa.h>

@class AccurateRipDiscRecord;

// ========================================
// A single track record from a disc in the AccurateRip database
// ========================================
@interface AccurateRipTrackRecord : NSManagedObject
{
}

// ========================================
// Core Data properties
@property (assign) NSNumber * number;
@property (assign) NSNumber * confidenceLevel;
@property (assign) NSNumber * CRC;

// ========================================
// Core Data relationships
@property (assign) AccurateRipDiscRecord * disc;

@end
