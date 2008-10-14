/*
 *  Copyright (C) 2007 - 2008 Stephen F. Booth <me@sbooth.org>
 *  All Rights Reserved
 */

#import <Cocoa/Cocoa.h>

@class AccurateRipDiscRecord, ExtractedTrackRecord;

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
@property (assign) NSNumber * checksum;
@property (assign) NSNumber * offsetChecksum;

// ========================================
// Core Data relationships
@property (assign) AccurateRipDiscRecord * disc;
@property (assign) NSSet * extractedTrackRecords;

@end

@interface AccurateRipTrackRecord (CoreDataGeneratedAccessors)
- (void) addExtractedTrackRecordsObject:(ExtractedTrackRecord *)value;
- (void) removeExtractedTrackRecordsObject:(ExtractedTrackRecord *)value;
- (void) addExtractedTrackRecords:(NSSet *)value;
- (void) removeExtractedTrackRecords:(NSSet *)value;
@end
