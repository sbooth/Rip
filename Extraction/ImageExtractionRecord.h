/*
 *  Copyright (C) 2008 Stephen F. Booth <me@sbooth.org>
 *  All Rights Reserved
 */

#import <Cocoa/Cocoa.h>

@class CompactDisc, DriveInformation, TrackExtractionRecord;

// ========================================
// This class represents one or more tracks extracted from a CDDA disc
// ========================================
@interface ImageExtractionRecord : NSManagedObject
{
}

// ========================================
// Core Data properties
@property (assign) NSDate * date;
@property (assign) NSString * MD5;
@property (assign) NSString * SHA1;
@property (assign) NSURL * URL;

// ========================================
// Core Data relationships
@property (assign) CompactDisc * disc;
@property (assign) DriveInformation * drive;
@property (assign) NSSet * tracks;

// ========================================
// Other properties
@property (readonly) NSArray * orderedTracks;
@property (readonly) TrackExtractionRecord * firstTrack;
@property (readonly) TrackExtractionRecord * lastTrack;

// ========================================

- (BOOL) containsTrackNumber:(NSUInteger)number;
- (TrackExtractionRecord *) trackNumber:(NSUInteger)number;

@end

@interface ImageExtractionRecord (CoreDataGeneratedAccessors)
- (void) addTracksObject:(TrackExtractionRecord *)value;
- (void) removeTracksObject:(TrackExtractionRecord *)value;
- (void) addTracks:(NSSet *)value;
- (void) removeTracks:(NSSet *)value;
@end
