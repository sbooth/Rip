/*
 *  Copyright (C) 2008 Stephen F. Booth <me@sbooth.org>
 *  All Rights Reserved
 */

#import "TrackMetadata.h"

@implementation TrackMetadata

// ========================================
// Core Data properties
@dynamic artist;
@dynamic composer;
@dynamic date;
@dynamic genre;
@dynamic ISRC;
@dynamic musicBrainzID;
@dynamic title;

// ========================================
// Core Data relationships
@dynamic track;

@end

