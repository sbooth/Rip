/*
 *  Copyright (C) 2005 - 2007 Stephen F. Booth <me@sbooth.org>
 *  All Rights Reserved
 */

#import "SessionDescriptor.h"
#import "TrackDescriptor.h"
#import "SectorRange.h"

@implementation SessionDescriptor

// ========================================
// Core Data properties
@dynamic leadOut;
@dynamic number;

// ========================================
// Core Data relationships
@dynamic disc;
@dynamic tracks;

// ========================================
// Other properties
- (NSSet *) selectedTracks
{
	NSPredicate *selectedTracksPredicate = [NSPredicate predicateWithFormat:@"isSelected == 1"];
	return [self.tracks filteredSetUsingPredicate:selectedTracksPredicate];
}

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
