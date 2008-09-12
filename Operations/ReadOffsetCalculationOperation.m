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

// ========================================
// KVC key names for the encoder dictionaries
// ========================================
NSString * const	kReadOffsetKey							= @"readOffset";
NSString * const	kConfidenceLevelKey						= @"confidenceLevel";

@interface ReadOffsetCalculationOperation ()
@property (assign) NSError * error;
@property (assign) NSArray * possibleReadOffsets;
@property (assign) NSNumber * fractionComplete;
@end

@implementation ReadOffsetCalculationOperation

@synthesize URL = _URL;
@synthesize trackDescriptorID = _trackDescriptorID;
@synthesize maximumOffsetToCheck = _maximumOffsetToCheck;
@synthesize error = _error;
@synthesize possibleReadOffsets = _possibleReadOffsets;
@synthesize fractionComplete = _fractionComplete;

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
	
	// Attempt to calculate the drive's offset using AccurateRip offset checksums
	// The offset checksum is the checksum for one single frame of audio starting at exactly six
	// seconds into the track
	
	// We will accomplish this by calculating AccurateRip checksums for the specified track using
	// different read offsets until a match is found
	TrackDescriptor *trackDescriptor = (TrackDescriptor *)managedObject;	
	
	if(!trackDescriptor) {
		self.error = [NSError errorWithDomain:NSCocoaErrorDomain code:1 userInfo:nil];
		return;
	}
	
	NSMutableArray *possibleReadOffsets = [NSMutableArray array];
	
	// Adjust the starting sector in the file
	SectorRange *singleSectorRange = [SectorRange sectorRangeWithFirstSector:(self.maximumOffsetToCheck.integerValue / AUDIO_FRAMES_PER_CDDA_SECTOR)
																 sectorCount:1];
	
	NSInteger firstOffsetToTry = -1 * self.maximumOffsetToCheck.integerValue;
	NSInteger lastOffsetToTry = self.maximumOffsetToCheck.integerValue;
	NSInteger currentOffset;
	
	for(currentOffset = firstOffsetToTry; currentOffset <= lastOffsetToTry; ++currentOffset) {

		// Allow cancellation
		if(self.isCancelled)
			break;
		
		// Calculate the AccurateRip checksum for this track with the specified offset
		uint32_t trackActualOffsetChecksum = calculateAccurateRipChecksumForFileRegionUsingOffset(self.URL, 
																								  singleSectorRange.firstSector,
																								  singleSectorRange.lastSector,
																								  trackDescriptor.number.unsignedIntegerValue == trackDescriptor.session.firstTrack.number.unsignedIntegerValue,
																								  trackDescriptor.number.unsignedIntegerValue == trackDescriptor.session.lastTrack.number.unsignedIntegerValue,
																								  currentOffset);

		// Check all the pressings that were found in AccurateRip for matching checksums
		for(AccurateRipDiscRecord *accurateRipDisc in trackDescriptor.session.disc.accurateRipDiscs) {
			
			// Determine what AccurateRip checksum we are attempting to match
			AccurateRipTrackRecord *accurateRipTrack = [accurateRipDisc trackNumber:trackDescriptor.number.unsignedIntegerValue];
			
			if(!accurateRipTrack) {
				self.error = [NSError errorWithDomain:NSCocoaErrorDomain code:1 userInfo:nil];
				continue;
			}

			// Ignore checksums of 0
			if(trackActualOffsetChecksum && accurateRipTrack.offsetChecksum.unsignedIntegerValue == trackActualOffsetChecksum) {
#if DEBUG
				NSLog(@"Possible drive offset of %i (%@)", currentOffset, accurateRipTrack.confidenceLevel);
#endif
				NSDictionary *offsetDictionary = [NSDictionary dictionaryWithObjectsAndKeys:
												  [NSNumber numberWithInteger:currentOffset], kReadOffsetKey,
												  accurateRipTrack.confidenceLevel, kConfidenceLevelKey,
												  nil];
				
				[possibleReadOffsets addObject:offsetDictionary];
			}
		}

		// Update progress
		self.fractionComplete = [NSNumber numberWithFloat:(fabsf(firstOffsetToTry - currentOffset) / (lastOffsetToTry - firstOffsetToTry))];
	}
	
	if(possibleReadOffsets.count)
		self.possibleReadOffsets = [possibleReadOffsets copy];
}

@end
