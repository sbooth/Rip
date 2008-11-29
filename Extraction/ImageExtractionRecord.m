/*
 *  Copyright (C) 2008 Stephen F. Booth <me@sbooth.org>
 *  All Rights Reserved
 */

#import "ImageExtractionRecord.h"
#import "TrackDescriptor.h"
#import "TrackExtractionRecord.h"

@implementation ImageExtractionRecord

// ========================================
// Core Data properties
@dynamic date;
@dynamic inputURL;
@dynamic MD5;
@dynamic outputURL;
@dynamic SHA1;

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

- (TrackExtractionRecord *) firstTrack
{
	NSArray *orderedTracks = self.orderedTracks;
	return (0 == orderedTracks.count ? nil : [orderedTracks objectAtIndex:0]);
}

- (TrackExtractionRecord *) lastTrack
{
	NSArray *orderedTracks = self.orderedTracks;
	return (0 == orderedTracks.count ? nil : orderedTracks.lastObject);
}

// ========================================

- (BOOL) containsTrackNumber:(NSUInteger)number
{
	return (nil != [self trackNumber:number]);
}

- (TrackExtractionRecord *) trackNumber:(NSUInteger)number
{
	for(TrackExtractionRecord *track in self.tracks) {
		if(track.track.number.unsignedIntegerValue == number)
			return track;
	}
	
	return nil;
}

@end
