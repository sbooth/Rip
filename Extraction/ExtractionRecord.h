/*
 *  Copyright (C) 2008 Stephen F. Booth <me@sbooth.org>
 *  All Rights Reserved
 */

#import <Cocoa/Cocoa.h>

@class CompactDisc, DriveInformation, ExtractedTrackRecord;

// ========================================
// This class represents one or more tracks extracted from a CDDA disc
// ========================================
@interface ExtractionRecord : NSManagedObject
{
}

// ========================================
// Core Data properties
@property (assign) NSDate * date;
@property (assign) NSString * MD5;
@property (assign) NSString * URL;

// ========================================
// Core Data relationships
@property (assign) CompactDisc * disc;
@property (assign) DriveInformation * drive;
@property (assign) NSSet * tracks;

// ========================================
// Other properties
@property (readonly) NSArray * orderedTracks;
@property (readonly) ExtractedTrackRecord * firstTrack;
@property (readonly) ExtractedTrackRecord * lastTrack;

// ========================================

- (BOOL) containsTrackNumber:(NSUInteger)number;
- (ExtractedTrackRecord *) trackNumber:(NSUInteger)number;

@end

// ========================================
// KVC accessors
@interface ExtractionRecord (CoreDataGeneratedAccessors)
- (void) addTracksObject:(ExtractedTrackRecord *)value;
- (void) removeTracksObject:(ExtractedTrackRecord *)value;
- (void) addTracks:(NSSet *)value;
- (void) removeTracks:(NSSet *)value;
@end
