/*
 *  Copyright (C) 2008 Stephen F. Booth <me@sbooth.org>
 *  All Rights Reserved
 */

#import <Cocoa/Cocoa.h>

@class BitArray, CompactDisc, DriveInformation;

// ========================================
// This class represents one or more tracks extracted from a CDDA disc
// ========================================
@interface ImageExtractionRecord : NSManagedObject
{
}

// ========================================
// Core Data properties
@property (assign) NSDate * date;
@property (assign) BitArray * errorFlags;
@property (assign) NSString * MD5;
@property (assign) NSString * SHA1;
@property (assign) NSURL * URL;

// ========================================
// Core Data relationships
@property (assign) CompactDisc * disc;
@property (assign) DriveInformation * drive;

#if 0
// ========================================
// Other properties
@property (readonly) NSArray * orderedTracks;

// ========================================

- (BOOL) containsTrackNumber:(NSUInteger)number;
- (TrackExtractionRecord *) trackNumber:(NSUInteger)number;
#endif

@end
