/*
 *  Copyright (C) 2005 - 2007 Stephen F. Booth <me@sbooth.org>
 *  All Rights Reserved
 */

#import "SectorRange.h"
#import "MutableSectorRange.h"

#include <IOKit/storage/IOCDTypes.h>

@interface SectorRange ()
@property (assign) NSUInteger firstSector;
@property (assign) NSUInteger lastSector;
@end

@implementation SectorRange

@synthesize firstSector = _firstSector;
@synthesize lastSector = _lastSector;

+ (id) sectorRangeWithSector:(NSUInteger)sector
{
	return [[[self class] alloc] initWithSector:sector];
}

+ (id) sectorRangeWithFirstSector:(NSUInteger)firstSector lastSector:(NSUInteger)lastSector
{
	return [[[self class] alloc] initWithFirstSector:firstSector lastSector:lastSector];
}

+ (id) sectorRangeWithFirstSector:(NSUInteger)firstSector sectorCount:(NSUInteger)sectorCount
{
	return [[[self class] alloc] initWithFirstSector:firstSector sectorCount:sectorCount];
}

- (id) initWithSector:(NSUInteger)sector
{
	return [self initWithFirstSector:sector lastSector:sector];
}

- (id) initWithFirstSector:(NSUInteger)firstSector lastSector:(NSUInteger)lastSector
{
	NSParameterAssert(lastSector >= firstSector);

	if((self = [super init])) {
		self.firstSector = firstSector;
		self.lastSector = lastSector;
	}
	return self;	
}

- (id) initWithFirstSector:(NSUInteger)firstSector sectorCount:(NSUInteger)sectorCount
{
	NSParameterAssert(0 < sectorCount);
	
	return [self initWithFirstSector:firstSector lastSector:(firstSector + sectorCount - 1)];
}

- (id) copyWithZone:(NSZone *)zone
{
	SectorRange *copy = [[SectorRange allocWithZone:zone] init];
	
	copy.firstSector = self.firstSector;
	copy.lastSector = self.lastSector;
	
	return copy;
}

- (id) mutableCopyWithZone:(NSZone *)zone
{
	MutableSectorRange *copy = [[MutableSectorRange allocWithZone:zone] init];
	
	copy.firstSector = self.firstSector;
	copy.lastSector = self.firstSector;
	
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
