/*
 *  Copyright (C) 2008 Stephen F. Booth <me@sbooth.org>
 *  All Rights Reserved
 */

#import "AlbumArtwork.h"

@implementation AlbumArtwork

// ========================================
// Core Data properties
@dynamic frontCover;

// ========================================
// Core Data relationships
@dynamic metadata;

// ========================================
// Computed properties
- (NSImage *) frontCoverImage
{
	if(!self.frontCover)
		return nil;
	
	NSData *frontCoverData = [NSUnarchiver unarchiveObjectWithData:self.frontCover];
	if(!frontCoverData)
		return nil;

	return [[NSImage alloc] initWithData:frontCoverData];
}

@end

