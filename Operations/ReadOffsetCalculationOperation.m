/*
 *  Copyright (C) 2008 - 2009 Stephen F. Booth <me@sbooth.org>
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
NSString * const	kAccurateRipTrackIDKey					= @"accurateRipTrackID";

@interface ReadOffsetCalculationOperation ()
@property (copy) NSError * error;
@property (copy) NSArray * possibleReadOffsets;
@property (assign) float fractionComplete;
@end

@implementation ReadOffsetCalculationOperation

@synthesize URL = _URL;
@synthesize trackID = _trackID;
@synthesize sixSecondPointSector = _sixSecondPointSector;
@synthesize maximumOffsetToCheck = _maximumOffsetToCheck;
@synthesize error = _error;
@synthesize possibleReadOffsets = _possibleReadOffsets;
@synthesize fractionComplete = _fractionComplete;

- (void) main
{
	NSParameterAssert(nil != self.URL);
	NSParameterAssert(nil != self.trackID);
	
	// Create our own context for accessing the store
	NSManagedObjectContext *managedObjectContext = [[NSManagedObjectContext alloc] init];
	[managedObjectContext setPersistentStoreCoordinator:[[[NSApplication sharedApplication] delegate] persistentStoreCoordinator]];
	
	// Fetch the TrackDescriptor object from the context and ensure it is the correct class
	NSManagedObject *managedObject = [managedObjectContext objectWithID:self.trackID];
	if(![managedObject isKindOfClass:[TrackDescriptor class]]) {
		self.error = [NSError errorWithDomain:NSOSStatusErrorDomain code:paramErr userInfo:nil];
		return;
	}
	
	// Attempt to calculate the drive's offset using AccurateRip offset checksums
	// The offset checksum is the checksum for one single frame of audio starting at exactly six
	// seconds into the track
	
	// We will accomplish this by calculating AccurateRip checksums for the specified track using
	// different read offsets until a match is found
	TrackDescriptor *trackDescriptor = (TrackDescriptor *)managedObject;	
	
	if(!trackDescriptor) {
		self.error = [NSError errorWithDomain:NSOSStatusErrorDomain code:paramErr userInfo:nil];
		return;
	}
	
	NSMutableArray *possibleReadOffsets = [NSMutableArray array];
	
	// Adjust the starting sector in the file
	NSRange singleSectorRange = NSMakeRange(self.sixSecondPointSector, 1);
	
	NSInteger firstOffsetToTry = -1 * self.maximumOffsetToCheck;
	NSInteger lastOffsetToTry = self.maximumOffsetToCheck;
	NSInteger currentOffset;
	for(currentOffset = firstOffsetToTry; currentOffset <= lastOffsetToTry; ++currentOffset) {

		// Allow cancellation
		if(self.isCancelled)
			break;
		
		// Calculate the AccurateRip checksum for this track with the specified offset
		uint32_t trackActualOffsetChecksum = calculateAccurateRipChecksumForFileRegionUsingOffset(self.URL, 
																								  singleSectorRange,
																								  NO,
																								  NO,
																								  currentOffset);

		// Check all the pressings that were found in AccurateRip for matching checksums
		for(AccurateRipDiscRecord *accurateRipDisc in trackDescriptor.session.disc.accurateRipDiscs) {
			
			// Determine what AccurateRip checksum we are attempting to match
			AccurateRipTrackRecord *accurateRipTrack = [accurateRipDisc trackNumber:trackDescriptor.number.unsignedIntegerValue];
			
			// If the track wasn't found or doesn't contain an offset checksum, it can't be used
			if(!accurateRipTrack || !accurateRipTrack.offsetChecksum)
				continue;

			if(accurateRipTrack.offsetChecksum.unsignedIntegerValue == trackActualOffsetChecksum) {
				NSDictionary *offsetDictionary = [NSDictionary dictionaryWithObjectsAndKeys:
												  [NSNumber numberWithInteger:currentOffset], kReadOffsetKey,
												  accurateRipTrack.confidenceLevel, kConfidenceLevelKey,
												  [accurateRipTrack objectID], kAccurateRipTrackIDKey,
												  nil];
				
				[possibleReadOffsets addObject:offsetDictionary];
			}
		}

		// Update progress
		self.fractionComplete = fabsf(firstOffsetToTry - currentOffset) / (float)(lastOffsetToTry - firstOffsetToTry);
	}
	
	if(possibleReadOffsets.count)
		self.possibleReadOffsets = possibleReadOffsets;
}

@end
