/*
 *  Copyright (C) 2008 Stephen F. Booth <me@sbooth.org>
 *  All Rights Reserved
 */

#import "ReadOffsetCalculationOperation.h"

#import "CompactDisc.h"
#import "SessionDescriptor.h"
#import "TrackDescriptor.h"

#import "AccurateRipDiscRecord.h"
#import "AccurateRipTrackRecord.h"
#import "AccurateRipUtilities.h"

#import "SectorRange.h"

#import "CDDAUtilities.h"

@interface ReadOffsetCalculationOperation ()
@property (assign) NSError * error;
@property (assign) NSNumber * readOffset;
@end

@implementation ReadOffsetCalculationOperation

@synthesize URL = _URL;
@synthesize trackDescriptorID = _trackDescriptorID;
@synthesize trackFirstSectorOffset = _trackFirstSectorOffset;
@synthesize maximumOffsetToCheck = _maximumOffsetToCheck;
@synthesize error = _error;
@synthesize readOffset = _readOffset;

- (void) main
{
	NSParameterAssert(nil != self.URL);
	NSParameterAssert(nil != self.trackDescriptorID);
	
	// Create our own context for accessing the store
	NSManagedObjectContext *managedObjectContext = [[NSManagedObjectContext alloc] init];
	[managedObjectContext setPersistentStoreCoordinator:[[[NSApplication sharedApplication] delegate] persistentStoreCoordinator]];
	
	// Fetch the TrackDescriptor object from the context and ensure it is the correct class
	NSManagedObject *managedObject = [managedObjectContext objectWithID:self.trackDescriptorID];
	if(![managedObject isKindOfClass:[TrackDescriptor class]]) {
		self.error = [NSError errorWithDomain:NSCocoaErrorDomain code:2 userInfo:nil];
		return;
	}
	
	// Attempt to calculate the drive's offset by brute force
	
	// We will accomplish this by calculating AccurateRip checksums for the specified track using
	// different read offsets until a match is found
	TrackDescriptor *trackDescriptor = (TrackDescriptor *)managedObject;	
	SectorRange *trackSectorRange = [trackDescriptor sectorRange];
	
	if(!trackDescriptor) {
		self.error = [NSError errorWithDomain:NSCocoaErrorDomain code:1 userInfo:nil];
		return;
	}
	
	// Determine what AccurateRip checksum we are attempting to match
	AccurateRipTrackRecord *accurateRipTrack = [trackDescriptor.session.disc.accurateRipDisc trackNumber:trackDescriptor.number.unsignedIntegerValue];

	if(!accurateRipTrack) {
		self.error = [NSError errorWithDomain:NSCocoaErrorDomain code:1 userInfo:nil];
		return;
	}

	// Adjust the starting sector in the file
	SectorRange *adjustedSectorRange = [SectorRange sectorRangeWithFirstSector:self.trackFirstSectorOffset.unsignedIntegerValue sectorCount:trackSectorRange.length];
	
	NSInteger firstOffsetToTry = -1 * self.maximumOffsetToCheck.integerValue;
	NSInteger lastOffsetToTry = self.maximumOffsetToCheck.integerValue;
	NSInteger currentOffset;
	
	for(currentOffset = firstOffsetToTry; currentOffset <= lastOffsetToTry; ++currentOffset) {
		if(self.isCancelled)
			break;

		uint32_t trackActualAccurateRipChecksum = calculateAccurateRipChecksumForFileRegionUsingOffset(self.URL, 
																									   adjustedSectorRange.firstSector,
																									   adjustedSectorRange.lastSector,
																									   NO,
																									   NO,
																									   currentOffset);
		
		if(accurateRipTrack.checksum.unsignedIntegerValue == trackActualAccurateRipChecksum) {
#if DEBUG
			NSLog(@"Calculated drive offset of %i", currentOffset);
#endif
			self.readOffset = [NSNumber numberWithInteger:currentOffset];
			return;
		}
	}
}

@end
