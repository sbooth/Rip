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
@dynamic MD5;
@dynamic SHA1;
@dynamic URL;

// ========================================
// Core Data relationships
@dynamic drive;
@dynamic track;

@end
