/*
 *  Copyright (C) 2008 Stephen F. Booth <me@sbooth.org>
 *  All Rights Reserved
 */

#import <Cocoa/Cocoa.h>

@class ExtractionRecord, TrackDescriptor;

// ========================================
// This class represents a single track extracted from a CDDA disc
// ========================================
@interface ExtractedTrackRecord : NSManagedObject
{
}

// ========================================
// Core Data properties
@property (assign) NSNumber * accurateRipChecksum;

// ========================================
// Core Data relationships
@property (assign) ExtractionRecord * extractionRecord;
@property (assign) TrackDescriptor * track;

@end
