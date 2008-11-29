/*
 *  Copyright (C) 2008 Stephen F. Booth <me@sbooth.org>
 *  All Rights Reserved
 */

#import "TrackExtractionRecord.h"

@implementation TrackExtractionRecord

// ========================================
// Core Data properties
@dynamic accurateRipChecksum;
@dynamic accurateRipAlternatePressingChecksum;
@dynamic accurateRipAlternatePressingOffset;
@dynamic accurateRipConfidenceLevel;
@dynamic blockErrorFlags;
@dynamic date;
@dynamic inputURL;
@dynamic MD5;
@dynamic outputURL;
@dynamic SHA1;

// ========================================
// Core Data relationships
@dynamic drive;
@dynamic track;
@dynamic image;

@end
