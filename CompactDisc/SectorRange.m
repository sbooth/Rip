/*
 *  Copyright (C) 2005 - 2009 Stephen F. Booth <me@sbooth.org>
 *  All Rights Reserved
 */

#import "SectorRange.h"

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
	return [[SectorRange alloc] initWithSector:sector];
}

+ (id) sectorRangeWithRange:(NSRange)range
{
	return [[SectorRange alloc] initWithRange:range];
}

+ (id) sectorRangeWithFirstSector:(NSUInteger)firstSector lastSector:(NSUInteger)lastSector
{
	return [[SectorRange alloc] initWithFirstSector:firstSector lastSector:lastSector];
}

+ (id) sectorRangeWithFirstSector:(NSUInteger)firstSector sectorCount:(NSUInteger)sectorCount
{
	return [[SectorRange alloc] initWithFirstSector:firstSector sectorCount:sectorCount];
}

+ (id) sectorRangeWithLastSector:(NSUInteger)lastSector sectorCount:(NSUInteger)sectorCount
{
	return [[SectorRange alloc] initWithLastSector:lastSector sectorCount:sectorCount];
}

- (id) initWithSector:(NSUInteger)sector
{
	return [self initWithFirstSector:sector lastSector:sector];
}

- (id) initWithRange:(NSRange)range
{
	return [self initWithFirstSector:range.location sectorCount:range.length];
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

- (id) initWithLastSector:(NSUInteger)lastSector sectorCount:(NSUInteger)sectorCount
{
	NSParameterAssert(0 < sectorCount);
	NSParameterAssert(0 < lastSector - sectorCount);
	
	return [self initWithFirstSector:(lastSector - sectorCount + 1) sectorCount:sectorCount];
}

#pragma mark NSCoding

- (id) initWithCoder:(NSCoder *)decoder
{
	NSParameterAssert(nil != decoder);
	
	if((self = [super init])) {
		self.firstSector = (NSUInteger)[decoder decodeIntegerForKey:@"SRFirstSector"];
		self.lastSector = (NSUInteger)[decoder decodeIntegerForKey:@"SRLastSector"];
	}
	
	return self;
}

- (void) encodeWithCoder:(NSCoder *)encoder
{
	NSParameterAssert(nil != encoder);
	
	[encoder encodeInteger:(NSInteger)self.firstSector forKey:@"SRFirstSector"];
	[encoder encodeInteger:(NSInteger)self.lastSector forKey:@"SRLastSector"];
}

#pragma mark NSCopying

- (id) copyWithZone:(NSZone *)zone
{
	SectorRange *copy = [[SectorRange allocWithZone:zone] init];
	
	copy.firstSector = self.firstSector;
	copy.lastSector = self.lastSector;
	
	return copy;
}

- (BOOL) isEqualToSectorRange:(SectorRange *)anotherSectorRange
{
	return (self.firstSector == anotherSectorRange.firstSector && self.lastSector == anotherSectorRange.lastSector);
}

- (NSUInteger)		length											{ return (self.lastSector - self.firstSector + 1); }
- (NSUInteger)		byteSize										{ return kCDSectorSizeCDDA * self.length; }

- (NSUInteger)		indexForSector:(NSUInteger)sector				{ return ([self containsSector:sector] ? sector - self.firstSector : NSNotFound); }
- (NSUInteger)		sectorForIndex:(NSUInteger)index				{ return (self.length > index ? self.firstSector + index : NSNotFound); }

- (BOOL)			containsSector:(NSUInteger)sector				{ return (self.firstSector <= sector && self.lastSector >= sector); }
- (BOOL)			containsSectorRange:(SectorRange *)range		{ return ([self containsSector:range.firstSector] && [self containsSector:range.lastSector]); }
- (BOOL)			intersectsSectorRange:(SectorRange *)range		{ return ([self containsSector:range.firstSector] || [self containsSector:range.lastSector]); }

- (SectorRange *) intersectedSectorRange:(SectorRange *)range
{
	NSParameterAssert(nil != range);
	
	NSUInteger firstSector = MAX(self.firstSector, range.firstSector);
	NSUInteger lastSector = MIN(self.lastSector, range.lastSector);
	
	return [[SectorRange alloc] initWithFirstSector:firstSector lastSector:lastSector];
}

- (NSRange) rangeValue
{
	return NSMakeRange(self.firstSector, self.length);
}

- (NSString *) description
{
	return [NSString stringWithFormat:@"SectorRange {\n\tfirstSector = %i,\n\tlastSector = %i,\n\tlength = %i\n}", self.firstSector, self.lastSector, self.length];
}

@end
