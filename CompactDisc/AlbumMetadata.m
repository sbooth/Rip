/*
 *  Copyright (C) 2008 Stephen F. Booth <me@sbooth.org>
 *  All Rights Reserved
 */

#import "AlbumMetadata.h"

@implementation AlbumMetadata

// ========================================
// Core Data properties
@dynamic artist;
@dynamic date;
@dynamic discNumber;
@dynamic discTotal;
@dynamic isCompilation;
@dynamic MCN;
@dynamic musicBrainzID;
@dynamic title;

// ========================================
// Core Data relationships
@dynamic artwork;
@dynamic disc;

- (void) awakeFromInsert
{
	// Create the artwork relationship
	self.artwork = [NSEntityDescription insertNewObjectForEntityForName:@"AlbumArtwork"
												 inManagedObjectContext:self.managedObjectContext];	
}

@end

