/*
 *  Copyright (C) 2008 Stephen F. Booth <me@sbooth.org>
 *  All Rights Reserved
 */

#import <Cocoa/Cocoa.h>

@class AlbumMetadata;

// ========================================
// This class encapsulates various types of album artwork
// ========================================
@interface AlbumArtwork : NSManagedObject
{
}

// ========================================
// Core Data properties
@property (assign) NSData * frontCover;

// ========================================
// Core Data relationships
@property (assign) AlbumMetadata * metadata;

@end
