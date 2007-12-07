/*
 *  $Id$
 *  Copyright (C) 2005 - 2007 Stephen F. Booth <me@sbooth.org>
 *  All Rights Reserved
 */

#import "SectorRange.h"

#include <IOKit/storage/IOCDTypes.h>

@implementation SectorRange

@synthesize firstSector = _firstSector;
@synthesize lastSector = _lastSector;

+ (id) sectorRangeWithFirstSector:(NSUInteger)firstSector lastSector:(NSUInteger)lastSector
{
	NSParameterAssert(lastSector >= firstSector);
	
	SectorRange *range = [[SectorRange alloc] init];
	
	range.firstSector = firstSector;
	range.lastSector= lastSector;
	
	return range;
}

+ (id) sectorRangeWithFirstSector:(NSUInteger)firstSector sectorCount:(NSUInteger)sectorCount
{
	NSParameterAssert(0 < sectorCount);

	SectorRange *range = [[SectorRange alloc] init];
	
	range.firstSector = firstSector;
	range.lastSector = firstSector + sectorCount - 1;
	
	return range;
}

+ (id) sectorRangeWithSector:(NSUInteger)sector
{
	SectorRange *range = [[SectorRange alloc] init];
	
	range.firstSector = sector;
	range.lastSector = sector;
	
	return range;
}

- (id) copyWithZone:(NSZone *)zone
{
	SectorRange *copy = [[[self class] allocWithZone:zone] init];
	
	copy.firstSector = self.firstSector;
	copy.lastSector = self.lastSector;
	
	return copy;
}

- (NSUInteger)		length											{ return (self.lastSector - self.firstSector + 1); }
- (NSUInteger)		byteSize										{ return kCDSectorSizeCDDA * self.length; }

- (NSUInteger)		indexForSector:(NSUInteger)sector				{ return ([self containsSector:sector] ? sector - self.firstSector : NSNotFound); }
- (NSUInteger)		sectorForIndex:(NSUInteger)index				{ return (self.length > index ? self.firstSector + index : NSNotFound); }

- (BOOL)			containsSector:(NSUInteger)sector				{ return (self.firstSector <= sector && self.lastSector >= sector); }
- (BOOL)			containsSectorRange:(SectorRange *)range		{ return ([self containsSector:range.firstSector] && [self containsSector:range.lastSector]); }

- (NSString *) description
{
	return [NSString stringWithFormat:@"SectorRange {\n\tfirstSector = %i,\n\tlastSector = %i,\n\tlength = %i\n}", self.firstSector, self.lastSector, self.length];
}

@end
