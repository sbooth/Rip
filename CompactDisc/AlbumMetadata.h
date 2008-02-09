/*
 *  Copyright (C) 2008 Stephen F. Booth <me@sbooth.org>
 *  All Rights Reserved
 */

#import <Cocoa/Cocoa.h>

@class CompactDisc;

// ========================================
// This class encapsulates metadata pertaining to an entire album
// ========================================
@interface AlbumMetadata : NSManagedObject
{
}

// ========================================
// Core Data properties
@property (assign) NSString * accurateRipURL;
@property (assign) NSString * artist;
@property (assign) NSString * composer;
@property (assign) NSString * date;
@property (assign) NSNumber * discNumber;
@property (assign) NSNumber * discTotal;
@property (assign) NSString * genre;
@property (assign) NSNumber * isCompilation;
@property (assign) NSString * MCN;
@property (assign) NSString * musicBrainzID;
@property (assign) NSString * title;

// ========================================
// Core Data relationships
@property (assign) CompactDisc * disc;

@end
