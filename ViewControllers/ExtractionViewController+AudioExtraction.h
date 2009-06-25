/*
 *  Copyright (C) 2008 - 2009 Stephen F. Booth <me@sbooth.org>
 *  All Rights Reserved
 */

#import <Cocoa/Cocoa.h>
#import "ExtractionViewController.h"

// ========================================
// Methods for extracting audio off the disc
// ========================================
@interface ExtractionViewController (AudioExtraction)
- (void) extractSectorRange:(SectorRange *)sectorRange;
- (void) extractSectorRange:(SectorRange *)sectorRange useC2:(BOOL)useC2;
- (void) extractSectorRange:(SectorRange *)sectorRange useC2:(BOOL)useC2 enforceMinimumReadSize:(BOOL)enforceMinimumReadSize;

- (void) extractSectors:(NSIndexSet *)sectorIndexes coalesceRanges:(BOOL)coalesceRanges;
@end
