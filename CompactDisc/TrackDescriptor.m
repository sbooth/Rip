/*
 *  Copyright (C) 2005 - 2007 Stephen F. Booth <me@sbooth.org>
 *  All Rights Reserved
 */

#import "TrackDescriptor.h"
#import "SectorRange.h"

@implementation TrackDescriptor

// ========================================
// KVC overrides
+ (NSSet *) keyPathsForValuesAffectingSectorCount
{
	return [NSSet setWithObjects:@"firstSector", @"lastSector", nil];
}

// ========================================
// Core Data properties
@dynamic channelsPerFrame;
@dynamic digitalCopyPermitted;
@dynamic firstSector;
@dynamic hasPreEmphasis;
@dynamic isDataTrack;
@dynamic isSelected;
@dynamic lastSector;
@dynamic number;
@dynamic pregap;

// ========================================
// Core Data relationships
@dynamic metadata;
@dynamic session;

// ========================================
// Computed properties
- (NSUInteger) sectorCount
{
	return self.sectorRange.length;
}

- (SectorRange *) sectorRange
{
	return [SectorRange sectorRangeWithFirstSector:self.firstSector.unsignedIntegerValue lastSector:self.lastSector.unsignedIntegerValue];
}

- (void) awakeFromInsert
{
	// Create the metadata relationship
	self.metadata = [NSEntityDescription insertNewObjectForEntityForName:@"TrackMetadata"
												  inManagedObjectContext:self.managedObjectContext];	
}

@end
