/*
 *  Copyright (C) 2005 - 2007 Stephen F. Booth <me@sbooth.org>
 *  All Rights Reserved
 */

#import <Cocoa/Cocoa.h>
#import "SectorRange.h"

// ========================================
// Mutable subclass of SectorRange
// ========================================
@interface MutableSectorRange : SectorRange
{
}

@property (assign) NSUInteger firstSector;
@property (assign) NSUInteger lastSector;

@end
