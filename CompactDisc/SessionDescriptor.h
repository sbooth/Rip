/*
 *  Copyright (C) 2005 - 2007 Stephen F. Booth <me@sbooth.org>
 *  All Rights Reserved
 */

#import <Cocoa/Cocoa.h>

@class CompactDisc, TrackDescriptor, SectorRange;

// ========================================
// This class encapsulates useful information about a single session on a CDDA disc
// ========================================
@interface SessionDescriptor : NSManagedObject
{
}

// ========================================
// Core Data properties
@property (assign) NSNumber * leadOut;
@property (assign) NSNumber * number;

// ========================================
// Core Data relationships
@property (assign) CompactDisc * compactDisc;
@property (assign) NSSet * tracks;

// ========================================
// Other properties
@property (readonly) NSSet * selectedTracks;
@property (readonly) NSArray * orderedTracks;
@property (readonly) TrackDescriptor * firstTrack;
@property (readonly) TrackDescriptor * lastTrack;

// ========================================

- (BOOL) containsTrackNumber:(NSUInteger)number;
- (TrackDescriptor *) trackNumber:(NSUInteger)number;

@end

// ========================================
// KVC accessors
@interface SessionDescriptor (CoreDataGeneratedAccessors)
- (void) addTracksObject:(TrackDescriptor *)value;
- (void) removeTracksObject:(TrackDescriptor *)value;
- (void) addTracks:(NSSet *)value;
- (void) removeTracks:(NSSet *)value;
@end
