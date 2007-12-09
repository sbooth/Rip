/*
 *  Copyright (C) 2005 - 2007 Stephen F. Booth <me@sbooth.org>
 *  All Rights Reserved
 */

#import <Cocoa/Cocoa.h>

// ========================================
// Utility class representing a contiguous, inclusive range
// of sectors on a CDDA disc
// ========================================
@interface SectorRange : NSObject <NSCopying>
{
	NSUInteger _firstSector;
	NSUInteger _lastSector;
}

@property (assign) NSUInteger firstSector;
@property (assign) NSUInteger lastSector;
@property (readonly) NSUInteger length;
@property (readonly) NSUInteger byteSize;

+ (id) sectorRangeWithFirstSector:(NSUInteger)firstSector lastSector:(NSUInteger)lastSector;
+ (id) sectorRangeWithFirstSector:(NSUInteger)firstSector sectorCount:(NSUInteger)sectorCount;
+ (id) sectorRangeWithSector:(NSUInteger)sector;

- (NSUInteger) indexForSector:(NSUInteger)sector;
- (NSUInteger) sectorForIndex:(NSUInteger)index;

- (BOOL) containsSector:(NSUInteger)sector;
- (BOOL) containsSectorRange:(SectorRange *)range;

@end
