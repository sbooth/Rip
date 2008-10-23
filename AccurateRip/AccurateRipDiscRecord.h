/*
 *  Copyright (C) 2007 - 2008 Stephen F. Booth <me@sbooth.org>
 *  All Rights Reserved
 */

#import <Cocoa/Cocoa.h>

@class CompactDisc, AccurateRipTrackRecord;

// ========================================
// Class providing access to information in the AccurateRip database
// for the given CompactDisc
// ========================================
@interface AccurateRipDiscRecord : NSManagedObject
{
}

// ========================================
// Core Data properties
@property (assign) NSURL * URL;

// ========================================
// Core Data relationships
@property (assign) CompactDisc * disc;
@property (assign) NSSet * tracks;

// ========================================
// Other properties
@property (readonly) NSArray * orderedTracks;
@property (readonly) AccurateRipTrackRecord * firstTrack;
@property (readonly) AccurateRipTrackRecord * lastTrack;
@property (readonly) BOOL isKeyDisc;

// ========================================

- (BOOL) containsTrackNumber:(NSUInteger)number;
- (AccurateRipTrackRecord *) trackNumber:(NSUInteger)number;

@end

@interface AccurateRipDiscRecord (CoreDataGeneratedAccessors)
- (void) addTracksObject:(AccurateRipTrackRecord *)value;
- (void) removeTracksObject:(AccurateRipTrackRecord *)value;
- (void) addTracks:(NSSet *)value;
- (void) removeTracks:(NSSet *)value;
@end
