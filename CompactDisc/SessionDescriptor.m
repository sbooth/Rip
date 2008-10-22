/*
 *  Copyright (C) 2005 - 2007 Stephen F. Booth <me@sbooth.org>
 *  All Rights Reserved
 */

#import "SessionDescriptor.h"
#import "TrackDescriptor.h"
#import "SectorRange.h"

@implementation SessionDescriptor

// ========================================
// Key dependencies
+ (NSSet *) keyPathsForValuesAffectingOrderedTracks
{
	return [NSSet setWithObject:@"tracks"];
}

+ (NSSet *) keyPathsForValuesAffectingFirstTrack
{
	return [NSSet setWithObject:@"tracks"];
}

+ (NSSet *) keyPathsForValuesAffectingLastTrack
{
	return [NSSet setWithObject:@"tracks"];
}

// ========================================
// Core Data properties
@dynamic leadOut;
@dynamic number;

// ========================================
// Core Data relationships
@dynamic disc;
@dynamic tracks;

// ========================================
// Computed properties
- (NSUInteger) sectorCount
{
	return self.sectorRange.length;
}

- (SectorRange *) sectorRange
{
	NSArray *orderedTracks = self.orderedTracks;
	
	if(0 == orderedTracks.count)
		return nil;
	
	TrackDescriptor *firstTrack = [orderedTracks objectAtIndex:0];
	TrackDescriptor *lastTrack = [orderedTracks lastObject];
	
	return [SectorRange sectorRangeWithFirstSector:firstTrack.firstSector.unsignedIntegerValue lastSector:lastTrack.lastSector.unsignedIntegerValue];
}

// ========================================
// Other properties
- (NSArray *) orderedTracks
{
	NSSortDescriptor *trackNumberSortDescriptor = [[NSSortDescriptor alloc] initWithKey:@"number" ascending:YES];
	return [self.tracks.allObjects sortedArrayUsingDescriptors:[NSArray arrayWithObject:trackNumberSortDescriptor]];
}

- (TrackDescriptor *) firstTrack
{
	NSArray *orderedTracks = self.orderedTracks;
	return (0 == orderedTracks.count ? nil : [orderedTracks objectAtIndex:0]);
}

- (TrackDescriptor *) lastTrack
{
	NSArray *orderedTracks = self.orderedTracks;
	return (0 == orderedTracks.count ? nil : orderedTracks.lastObject);
}

- (NSSet *) selectedTracks
{
	NSPredicate *selectedTracksPredicate = [NSPredicate predicateWithFormat:@"isSelected == 1"];
	return [self.tracks filteredSetUsingPredicate:selectedTracksPredicate];
}

- (NSArray *) orderedSelectedTracks
{
	NSSortDescriptor *trackNumberSortDescriptor = [[NSSortDescriptor alloc] initWithKey:@"number" ascending:YES];
	return [self.selectedTracks.allObjects sortedArrayUsingDescriptors:[NSArray arrayWithObject:trackNumberSortDescriptor]];
}

// ========================================

- (BOOL) containsTrackNumber:(NSUInteger)number
{
	return (nil != [self trackNumber:number]);
}

- (TrackDescriptor *) trackNumber:(NSUInteger)number
{
	for(TrackDescriptor *track in self.tracks) {
		if(track.number.unsignedIntegerValue == number)
			return track;
	}
	
	return nil;
}

@end
