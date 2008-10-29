/*
 *  Copyright (C) 2008 Stephen F. Booth <me@sbooth.org>
 *  All Rights Reserved
 */

#import <Cocoa/Cocoa.h>

@class CompactDisc, AlbumArtwork;

// ========================================
// This class encapsulates metadata pertaining to an entire album
// ========================================
@interface AlbumMetadata : NSManagedObject
{
}

// ========================================
// Core Data properties
@property (assign) NSString * artist;
@property (assign) NSString * date;
@property (assign) NSNumber * discNumber;
@property (assign) NSNumber * discTotal;
@property (assign) NSNumber * isCompilation;
@property (assign) NSString * MCN;
@property (assign) NSString * musicBrainzID;
@property (assign) NSString * title;

// ========================================
// Core Data relationships
@property (assign) NSSet * artwork;
@property (assign) CompactDisc * disc;

@end
