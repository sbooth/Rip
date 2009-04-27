/*
 *  Copyright (C) 2008 - 2009 Stephen F. Booth <me@sbooth.org>
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
@property (assign) NSDictionary * additionalMetadata;
@property (assign) NSString * artist;
@property (assign) NSString * date;
@property (assign) NSNumber * discNumber;
@property (assign) NSNumber * discTotal;
@property (assign) NSNumber * isCompilation;
@property (assign) NSString * MCN;
@property (assign) NSString * musicBrainzID;
@property (assign) NSNumber * peak;
@property (assign) NSNumber * replayGain;
@property (assign) NSString * title;

// ========================================
// Core Data relationships
@property (assign) AlbumArtwork * artwork;
@property (assign) CompactDisc * disc;

@end
