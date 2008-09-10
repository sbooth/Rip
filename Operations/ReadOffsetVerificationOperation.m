/*
 *  Copyright (C) 2008 Stephen F. Booth <me@sbooth.org>
 *  All Rights Reserved
 */

#import "ReadOffsetVerificationOperation.h"

#import "CompactDisc.h"
#import "SessionDescriptor.h"
#import "TrackDescriptor.h"

#import "AccurateRipDiscRecord.h"
#import "AccurateRipTrackRecord.h"
#import "AccurateRipUtilities.h"

#import "SectorRange.h"

#import "CDDAUtilities.h"

@interface ReadOffsetVerificationOperation ()
@property (assign) NSError * error;
@property (assign) NSNumber * offsetVerified;
@end

@implementation ReadOffsetVerificationOperation

@synthesize URL = _URL;
@synthesize trackDescriptorID = _trackDescriptorID;
@synthesize trackFirstSectorOffset = _trackFirstSectorOffset;
@synthesize offsetToVerify = _offsetToVerify;
@synthesize error = _error;
@synthesize offsetVerified = _offsetVerified;

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
	
	// Attempt to verify the drive's read offset
	SectorRange *adjustedSectorRange = [SectorRange sectorRangeWithFirstSector:self.trackFirstSectorOffset.unsignedIntegerValue sectorCount:trackSectorRange.length];
	uint32_t trackActualAccurateRipChecksum = calculateAccurateRipChecksumForFileRegionUsingOffset(self.URL, 
																								   adjustedSectorRange.firstSector,
																								   adjustedSectorRange.lastSector,
																								   NO,
																								   NO,
																								   self.offsetToVerify.unsignedIntegerValue);

	if(accurateRipTrack.checksum.unsignedIntegerValue == trackActualAccurateRipChecksum)
		self.offsetVerified = [NSNumber numberWithBool:YES];
	else	
		self.offsetVerified = [NSNumber numberWithBool:NO];
}

@end
