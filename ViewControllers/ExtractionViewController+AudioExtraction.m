/*
 *  Copyright (C) 2008 - 2009 Stephen F. Booth <me@sbooth.org>
 *  All Rights Reserved
 */

#import "ExtractionViewController+AudioExtraction.h"

#import "DriveInformation.h"

#import "SectorRange.h"
#import "CompactDisc.h"
#import "SessionDescriptor.h"

#import "ExtractionOperation.h"

#import "FileUtilities.h"

#include <IOKit/storage/IOCDTypes.h>

@implementation ExtractionViewController (AudioExtraction)

- (void) extractSectorRange:(SectorRange *)sectorRange
{
	[self extractSectorRange:sectorRange useC2:[self.driveInformation.useC2 boolValue] enforceMinimumReadSize:NO];
}

- (void) extractSectorRange:(SectorRange *)sectorRange useC2:(BOOL)useC2
{
	[self extractSectorRange:sectorRange useC2:useC2 enforceMinimumReadSize:NO];
}

- (void) extractSectorRange:(SectorRange *)sectorRange useC2:(BOOL)useC2 enforceMinimumReadSize:(BOOL)enforceMinimumReadSize
{
	NSParameterAssert(nil != sectorRange);
	
	// Should a block of at least MINIMUM_DISC_READ_SIZE be read?
	if(enforceMinimumReadSize && MINIMUM_DISC_READ_SIZE > sectorRange.byteSize) {
		NSUInteger sizeIncrease = MINIMUM_DISC_READ_SIZE - sectorRange.byteSize;
		NSUInteger sectorOffset = ((sizeIncrease / 2)  / kCDSectorSizeCDDA) + 1;
		
		NSUInteger newFirstSector = sectorRange.firstSector;
		if(newFirstSector > sectorOffset)
			newFirstSector -= sectorOffset;
		NSUInteger newLastSector = sectorRange.lastSector + sectorOffset;
		
		sectorRange = [SectorRange sectorRangeWithFirstSector:newFirstSector lastSector:newLastSector];
	}
	
	// Audio extraction
	ExtractionOperation *extractionOperation = [[ExtractionOperation alloc] init];
	
	extractionOperation.disk = self.disk;
	extractionOperation.sectors = sectorRange;
	extractionOperation.allowedSectors = self.compactDisc.firstSession.sectorRange;
	extractionOperation.readOffset = self.driveInformation.readOffset;
	extractionOperation.URL = temporaryURLWithExtension(@"wav");
	extractionOperation.useC2 = useC2;
	
	// Observe the operation's progress
	[extractionOperation addObserver:self forKeyPath:@"isExecuting" options:NSKeyValueObservingOptionNew context:kAudioExtractionKVOContext];
	[extractionOperation addObserver:self forKeyPath:@"isCancelled" options:NSKeyValueObservingOptionNew context:kAudioExtractionKVOContext];
	[extractionOperation addObserver:self forKeyPath:@"isFinished" options:NSKeyValueObservingOptionNew context:kAudioExtractionKVOContext];
	
	// Do it.  Do it.  Do it.
	[self.operationQueue addOperation:extractionOperation];
}

- (void) extractSectors:(NSIndexSet *)sectorIndexes coalesceRanges:(BOOL)coalesceRanges
{
	NSParameterAssert(nil != sectorIndexes);
	
	// Coalesce the index set into ranges to minimize the number of disc accesses
	if(coalesceRanges) {
		NSUInteger firstIndex = NSNotFound;
		NSUInteger latestIndex = NSNotFound;
		NSUInteger sectorIndex = [sectorIndexes firstIndex];
		
		for(;;) {
			// Last sector
			if(NSNotFound == sectorIndex) {
				if(NSNotFound != firstIndex) {
					if(firstIndex == latestIndex)
						[self extractSectorRange:[SectorRange sectorRangeWithSector:firstIndex] useC2:[self.driveInformation.useC2 boolValue] enforceMinimumReadSize:YES];
					else
						[self extractSectorRange:[SectorRange sectorRangeWithFirstSector:firstIndex lastSector:latestIndex] useC2:[self.driveInformation.useC2 boolValue] enforceMinimumReadSize:YES];
				}
				
				break;
			}
			
			// Consolidate this sector into the current range
			if(latestIndex == (sectorIndex - 1))
				latestIndex = sectorIndex;
			// Store the previous range and start a new one
			else {
				if(NSNotFound != firstIndex) {
					if(firstIndex == latestIndex)
						[self extractSectorRange:[SectorRange sectorRangeWithSector:firstIndex] useC2:[self.driveInformation.useC2 boolValue] enforceMinimumReadSize:YES];
					else /*if(firstIndex + 891 < latestIndex)*/
						[self extractSectorRange:[SectorRange sectorRangeWithFirstSector:firstIndex lastSector:latestIndex] useC2:[self.driveInformation.useC2 boolValue] enforceMinimumReadSize:YES];
				}
				
				firstIndex = sectorIndex;
				latestIndex = sectorIndex;
			}
			
			sectorIndex = [sectorIndexes indexGreaterThanIndex:sectorIndex];
		}
	}
	else {
		NSUInteger sectorIndex = [sectorIndexes firstIndex];
		while(NSNotFound != sectorIndex) {
			[self extractSectorRange:[SectorRange sectorRangeWithSector:sectorIndex] useC2:[self.driveInformation.useC2 boolValue] enforceMinimumReadSize:YES];
			sectorIndex = [sectorIndexes indexGreaterThanIndex:sectorIndex];			
		}
		
	}	
}

@end
