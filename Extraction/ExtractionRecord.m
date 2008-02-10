/*
 *  Copyright (C) 2008 Stephen F. Booth <me@sbooth.org>
 *  All Rights Reserved
 */

#import "ExtractionRecord.h"
#import "ExtractedTrackRecord.h"
#import "TrackDescriptor.h"

@implementation ExtractionRecord

// ========================================
// Core Data properties
@dynamic date;
@dynamic MD5;
@dynamic URL;

// ========================================
// Core Data relationships
@dynamic disc;
@dynamic drive;
@dynamic tracks;

// ========================================
// Other properties
- (NSArray *) orderedTracks
{
	NSSortDescriptor *trackNumberSortDescriptor = [[NSSortDescriptor alloc] initWithKey:@"track.number" ascending:YES];
	return [self.tracks.allObjects sortedArrayUsingDescriptors:[NSArray arrayWithObject:trackNumberSortDescriptor]];
}

- (ExtractedTrackRecord *) firstTrack
{
	NSArray *orderedTracks = self.orderedTracks;
	return (0 == orderedTracks.count ? nil : [orderedTracks objectAtIndex:0]);
}

- (ExtractedTrackRecord *) lastTrack
{
	NSArray *orderedTracks = self.orderedTracks;
	return (0 == orderedTracks.count ? nil : orderedTracks.lastObject);
}

// ========================================

- (BOOL) containsTrackNumber:(NSUInteger)number
{
	return (nil != [self trackNumber:number]);
}

- (ExtractedTrackRecord *) trackNumber:(NSUInteger)number
{
	for(ExtractedTrackRecord *track in self.tracks) {
		if(track.track.number.unsignedIntegerValue == number)
			return track;
	}
	
	return nil;
}
@end
