/*
 *  Copyright (C) 2005 - 2009 Stephen F. Booth <me@sbooth.org>
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
@property (assign) CompactDisc * disc;
@property (assign) NSSet * tracks;

// ========================================
// Computed properties
@property (readonly) NSUInteger sectorCount;
@property (readonly) SectorRange * sectorRange;

// ========================================
// Other properties
@property (readonly) NSArray * orderedTracks;
@property (readonly) TrackDescriptor * firstTrack;
@property (readonly) TrackDescriptor * lastTrack;

@property (readonly) NSSet * selectedTracks;
@property (readonly) NSArray * orderedSelectedTracks;

// ========================================

- (BOOL) containsTrackNumber:(NSUInteger)number;
- (TrackDescriptor *) trackNumber:(NSUInteger)number;

// ========================================

- (TrackDescriptor *) trackContainingSector:(NSUInteger)sector;
- (TrackDescriptor *) trackContainingSectorRange:(SectorRange *)sectorRange;

@end

// ========================================
// KVC accessors
@interface SessionDescriptor (CoreDataGeneratedAccessors)
- (void) addTracksObject:(TrackDescriptor *)value;
- (void) removeTracksObject:(TrackDescriptor *)value;
- (void) addTracks:(NSSet *)value;
- (void) removeTracks:(NSSet *)value;
@end
