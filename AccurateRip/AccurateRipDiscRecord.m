/*
 *  Copyright (C) 2007 - 2008 Stephen F. Booth <me@sbooth.org>
 *  All Rights Reserved
 */

#import "AccurateRipDiscRecord.h"
#import "AccurateRipTrackRecord.h"

@implementation AccurateRipDiscRecord

// ========================================
// Core Data properties
@dynamic URL;

// ========================================
// Core Data relationships
@dynamic disc;
@dynamic tracks;

// ========================================
// Other properties
- (NSArray *) orderedTracks
{
	NSSortDescriptor *trackNumberSortDescriptor = [[NSSortDescriptor alloc] initWithKey:@"number" ascending:YES];
	return [self.tracks.allObjects sortedArrayUsingDescriptors:[NSArray arrayWithObject:trackNumberSortDescriptor]];
}

- (AccurateRipTrackRecord *) firstTrack
{
	NSArray *orderedTracks = self.orderedTracks;
	return (0 == orderedTracks.count ? nil : [orderedTracks objectAtIndex:0]);
}

- (AccurateRipTrackRecord *) lastTrack
{
	NSArray *orderedTracks = self.orderedTracks;
	return (0 == orderedTracks.count ? nil : orderedTracks.lastObject);
}

// ========================================

- (BOOL) containsTrackNumber:(NSUInteger)number
{
	return (nil != [self trackNumber:number]);
}

- (AccurateRipTrackRecord *) trackNumber:(NSUInteger)number
{
	for(AccurateRipTrackRecord *track in self.tracks) {
		if(track.number.unsignedIntegerValue == number)
			return track;
	}
	
	return nil;
}

@end
