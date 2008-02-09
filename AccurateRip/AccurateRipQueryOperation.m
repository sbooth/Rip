/*
 *  Copyright (C) 2008 Stephen F. Booth <me@sbooth.org>
 *  All Rights Reserved
 */

#import "AccurateRipQueryOperation.h"
#import "CompactDisc.h"
#import "SessionDescriptor.h"
#import "TrackDescriptor.h"
#import "AccurateRipDiscRecord.h"
#import "AccurateRipTrackRecord.h"

@interface AccurateRipQueryOperation ()
@property (assign) NSError *error;
@end

@implementation AccurateRipQueryOperation

// ========================================
// Properties
@synthesize compactDiscID = _compactDiscID;
@synthesize error = _error;

- (void) main
{
	NSAssert(nil != self.compactDiscID, @"self.compactDiscID may not be nil");

	// Create our own context for accessing the store
	NSManagedObjectContext *managedObjectContext = [[NSManagedObjectContext alloc] init];
	[managedObjectContext setPersistentStoreCoordinator:[[[NSApplication sharedApplication] delegate] persistentStoreCoordinator]];
	
	// Fetch the CompactDisc object from the context and ensure it is the correct class
	NSManagedObject *managedObject = [managedObjectContext objectWithID:self.compactDiscID];
	if(![managedObject isKindOfClass:[CompactDisc class]]) {
		self.error = [NSError errorWithDomain:NSCocoaErrorDomain code:2 userInfo:nil];
		return;
	}
	
	CompactDisc *compactDisc = (CompactDisc *)managedObject;

	NSUInteger accurateRipID1 = compactDisc.accurateRipID1.unsignedIntegerValue;
	NSUInteger accurateRipID2 = compactDisc.accurateRipID2.unsignedIntegerValue;

	// Use the first session
	NSSet *sessionTracks = compactDisc.firstSession.tracks;
	
	// Build the URL
	NSURL *accurateRipURL = [NSURL URLWithString:[NSString stringWithFormat:@"http://www.accuraterip.com/accuraterip/%.1x/%.1x/%.1x/dBAR-%.3d-%.8x-%.8x-%.8x.bin",
												  accurateRipID1 & 0x0F,
												  (accurateRipID1 >> 4) & 0x0F,
												  (accurateRipID1 >> 8) & 0x0F,
												  sessionTracks.count,
												  accurateRipID1,
												  accurateRipID2,
												  compactDisc.discID.integerValue]];
	
	// Create a request for the URL with a 2 minute timeout
	NSURLRequest *request = [NSURLRequest requestWithURL:accurateRipURL
											 cachePolicy:NSURLRequestUseProtocolCachePolicy
										 timeoutInterval:120.0];
	
	NSURLResponse *accurateRipResponse = nil;
	NSError *error = nil;
	NSData *accurateRipResponseData = [NSURLConnection sendSynchronousRequest:request 
															returningResponse:&accurateRipResponse 
																		error:&error];
	if(nil == accurateRipResponseData) {
		self.error = error;
		return;
	}
	
	// An Accurate Rip .bin file is formatted as follows:
	//
	// 1 byte for the number of tracks on the disc  [arTrackCount]
	// 4 bytes (LE) for the Accurate Rip Disc ID 1  [arDiscID1]
	// 4 bytes (LE) for the Accurate Rip Disc ID 2  [arDiscID2]
	// 4 bytes (LE) for the disc's FreeDB ID		[arFreeDBID]
	// 
	// A variable number [arTrackCount] of track records:
	//
	//  1 byte for the confidence level				[arTrackConfidence]
	//  4 bytes (LE) for the track's CRC			[arTrackCRC]
	//  4 bytes ????
	
	// Use the first session
	NSArray *orderedTracks = compactDisc.firstSession.orderedTracks;
	
	uint8_t arTrackCount = 0;
	[accurateRipResponseData getBytes:&arTrackCount range:NSMakeRange(0, 1)];
	
	uint32_t arDiscID1 = 0;
	[accurateRipResponseData getBytes:&arDiscID1 range:NSMakeRange(1, 4)];
	arDiscID1 = OSSwapLittleToHostInt32(arDiscID1);
	
	uint32_t arDiscID2 = 0;
	[accurateRipResponseData getBytes:&arDiscID2 range:NSMakeRange(5, 4)];
	arDiscID2 = OSSwapLittleToHostInt32(arDiscID2);
	
	int32_t arFreeDBID = 0;
	[accurateRipResponseData getBytes:&arFreeDBID range:NSMakeRange(9, 4)];
	arFreeDBID = OSSwapLittleToHostInt32(arFreeDBID);

	if(arTrackCount != orderedTracks.count || arDiscID1 != accurateRipID1 || arDiscID2 != accurateRipID2 || arFreeDBID != compactDisc.discID.intValue) {

#if DEBUG
		NSLog(@"AccurateRip track count or disc IDs don't match.");
#endif

		self.error = [NSError errorWithDomain:NSCocoaErrorDomain code:3 userInfo:nil];
		return;
	}
	
	// Create an AccurateRipDiscRecord object if one doesn't exist for this CompactDisc
	AccurateRipDiscRecord *accurateRipDisc = compactDisc.accurateRipDisc;
	if(!accurateRipDisc) {
		accurateRipDisc = [NSEntityDescription insertNewObjectForEntityForName:@"AccurateRipDiscRecord" 
														inManagedObjectContext:managedObjectContext];
		
		compactDisc.accurateRipDisc = accurateRipDisc;		
	}
	
	accurateRipDisc.URL = accurateRipURL.absoluteString;
	
	NSUInteger i, offset = 13;
	for(i = 0; i < arTrackCount; ++i) {
		uint8_t arTrackConfidence = 0;
		[accurateRipResponseData getBytes:&arTrackConfidence range:NSMakeRange(offset, 1)];
		
		// An AccurateRip track CRC is calculated as follows:
		//
		// Since this is CD-DA audio, a block (sector) is 2352 bytes in size and 1/75th of a second in duration
		// A single 2352 byte block contains 588 audio frames at 16 bits per channel and 2 channels
		//
		// For CRC calculations, AccurateRip treats a single audio frame of as a 32-bit quantity
		//
		// Multiply the audio frame's value (as an (unsigned?) 32-bit integer) [f(n)] times it's frame number [n]
		// The first four blocks and 587 frames of the first track are skipped (zero CRC value)
		// The last six blocks of the last track are skipped (zero CRC value)
		//
		// The CRC is additive
		
		uint32_t arTrackCRC = 0;
		[accurateRipResponseData getBytes:&arTrackCRC range:NSMakeRange(offset + 1, 4)];
		arTrackCRC = OSSwapLittleToHostInt32(arTrackCRC);
		
/*		uint32_t arTrackStartCRC = 0;
		[self.responseData getBytes:&arTrackStartCRC range:NSMakeRange(offset + 1 + 4, 4)];
		arTrackStartCRC = OSSwapLittleToHostInt32(arTrackStartCRC); */
		
		// What are the next 4 bytes?
		
		offset += 9;
		
		// Add the AccurateRipTrackRecord to the AccurateRipDiscRecord if one doesn't exist for this track
		AccurateRipTrackRecord *accurateRipTrack = [accurateRipDisc trackNumber:(1 + i)];
		if(!accurateRipTrack) {
			accurateRipTrack = [NSEntityDescription insertNewObjectForEntityForName:@"AccurateRipTrackRecord" 
															 inManagedObjectContext:accurateRipDisc.managedObjectContext];	
			
			accurateRipTrack.number = [NSNumber numberWithUnsignedInteger:(1 + i)];
			
			[accurateRipDisc addTracksObject:accurateRipTrack];
		}
		
		accurateRipTrack.confidenceLevel = [NSNumber numberWithUnsignedInteger:arTrackConfidence];
		accurateRipTrack.CRC = [NSNumber numberWithUnsignedInteger:arTrackCRC];		
	}	

	// Save the changes
	if(managedObjectContext.hasChanges) {
		if(![managedObjectContext save:&error])
			self.error = error;
	}
}

@end
