/*
 *  Copyright (C) 2008 Stephen F. Booth <me@sbooth.org>
 *  All Rights Reserved
 */

#import "AlbumMetadata.h"

@implementation AlbumMetadata

// ========================================
// Core Data properties
@dynamic accurateRipURL;
@dynamic artist;
@dynamic composer;
@dynamic date;
@dynamic discNumber;
@dynamic discTotal;
@dynamic genre;
@dynamic isCompilation;
@dynamic MCN;
@dynamic musicBrainzID;
@dynamic title;

// ========================================
// Core Data relationships
@dynamic disc;

@end

