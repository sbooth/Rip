/*
 *  Copyright (C) 2008 Stephen F. Booth <me@sbooth.org>
 *  All Rights Reserved
 */

// Access to AccurateRip is regulated, see http://www.accuraterip.com/3rdparty-access.htm for details

#import "AccurateRipQueryOperation.h"
#import "CompactDisc.h"
#import "SessionDescriptor.h"
#import "TrackDescriptor.h"
#import "AccurateRipDiscRecord.h"
#import "AccurateRipTrackRecord.h"
#import "Logger.h"

#include <SystemConfiguration/SCNetwork.h>

@interface AccurateRipQueryOperation ()
@property (copy) NSError *error;
@end

@implementation AccurateRipQueryOperation

// ========================================
// Properties
@synthesize compactDiscID = _compactDiscID;
@synthesize error = _error;

- (void) main
{
	NSAssert(nil != self.compactDiscID, @"self.compactDiscID may not be nil");

	// Before doing anything, verify we can access the AccurateRip web site
	SCNetworkConnectionFlags flags;
	if(SCNetworkCheckReachabilityByName("www.accuraterip.com", &flags)) {
		if(!(kSCNetworkFlagsReachable & flags && !(kSCNetworkFlagsConnectionRequired & flags))) {
			NSMutableDictionary *errorDictionary = [NSMutableDictionary dictionary];
			[errorDictionary setObject:[NSURL URLWithString:@"www.accuraterip.com"] forKey:NSErrorFailingURLStringKey];
			
			self.error = [NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorCannotConnectToHost userInfo:errorDictionary];
			return;
		}
	}
	
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

	NSUInteger accurateRipID1 = compactDisc.accurateRipID1;
	NSUInteger accurateRipID2 = compactDisc.accurateRipID2;

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
												  compactDisc.freeDBDiscID]];
	
	// Create a request for the URL with a 2 minute timeout
	NSURLRequest *request = [NSURLRequest requestWithURL:accurateRipURL
											 cachePolicy:NSURLRequestUseProtocolCachePolicy
										 timeoutInterval:120.0];
	
	NSURLResponse *accurateRipResponse = nil;
	NSError *error = nil;
	NSData *accurateRipResponseData = [NSURLConnection sendSynchronousRequest:request 
															returningResponse:&accurateRipResponse 
																		error:&error];
	if(!accurateRipResponseData) {
		self.error = error;
		return;
	}
	
	// Remove any existing AccurateRip data (it will be replaced)
	NSSet *existingAccurateRipDiscs = [compactDisc.accurateRipDiscs copy];
	[compactDisc removeAccurateRipDiscs:existingAccurateRipDiscs];
	
	// Delete them from the store
	for(NSManagedObject *managedObjectToDelete in existingAccurateRipDiscs)
		[managedObjectContext deleteObject:managedObjectToDelete];
	
	// Use the first session
	NSArray *orderedTracks = compactDisc.firstSession.orderedTracks;
	
	// An Accurate Rip .bin file is formatted as follows:
	//
	// A variable number of disc pressing records containing:
	//
	//  1 byte for the number of tracks on the disc		[arTrackCount]
	//  4 bytes (LE) for the Accurate Rip Disc ID 1		[arDiscID1]
	//  4 bytes (LE) for the Accurate Rip Disc ID 2		[arDiscID2]
	//  4 bytes (LE) for the disc's FreeDB ID			[arFreeDBID]
	// 
	//  A variable number [arTrackCount] of track records:
	//
	//   1 byte for the confidence level				[arTrackConfidence]
	//   4 bytes (LE) for the track's CRC				[arTrackCRC]
	//   4 bytes (LE) for offset CRC					[arOffsetChecksum]
	
	NSUInteger accurateRipDiscDataSize = (1 + 4 + 4 + 4) + (orderedTracks.count * (1 + 4 + 4));
	NSUInteger accurateRipPressingCount = [accurateRipResponseData length] / accurateRipDiscDataSize;
	
	NSUInteger pressingDataOffset = 0;
	NSUInteger pressingIndex;
	for(pressingIndex = 0; pressingIndex < accurateRipPressingCount; ++pressingIndex) {
		uint8_t arTrackCount = 0;
		[accurateRipResponseData getBytes:&arTrackCount range:NSMakeRange(pressingDataOffset, 1)];
		
		uint32_t arDiscID1 = 0;
		[accurateRipResponseData getBytes:&arDiscID1 range:NSMakeRange(pressingDataOffset + 1, 4)];
		arDiscID1 = OSSwapLittleToHostInt32(arDiscID1);
		
		uint32_t arDiscID2 = 0;
		[accurateRipResponseData getBytes:&arDiscID2 range:NSMakeRange(pressingDataOffset + 5, 4)];
		arDiscID2 = OSSwapLittleToHostInt32(arDiscID2);
		
		int32_t arFreeDBID = 0;
		[accurateRipResponseData getBytes:&arFreeDBID range:NSMakeRange(pressingDataOffset + 9, 4)];
		arFreeDBID = OSSwapLittleToHostInt32(arFreeDBID);
		
		if(arTrackCount != orderedTracks.count || arDiscID1 != accurateRipID1 || arDiscID2 != accurateRipID2 || (NSUInteger)arFreeDBID != compactDisc.freeDBDiscID) {
			[[Logger sharedLogger] logMessageWithLevel:eLogMessageLevelDebug format:@"AccurateRip track count or disc IDs don't match."];
			
			self.error = [NSError errorWithDomain:NSCocoaErrorDomain code:3 userInfo:nil];
			continue;
		}
		
		// Create an AccurateRipDiscRecord object 
		AccurateRipDiscRecord *accurateRipDisc = [NSEntityDescription insertNewObjectForEntityForName:@"AccurateRipDiscRecord" 
																			   inManagedObjectContext:managedObjectContext];
		
		[compactDisc addAccurateRipDiscsObject:accurateRipDisc];
		
		accurateRipDisc.URL = accurateRipURL;

		NSUInteger i;
		NSUInteger trackDataOffset = pressingDataOffset + (1 + 4 + 4 + 4);
		for(i = 0; i < arTrackCount; ++i) {
			uint8_t arTrackConfidence = 0;
			[accurateRipResponseData getBytes:&arTrackConfidence range:NSMakeRange(trackDataOffset, 1)];
			
			// An AccurateRip track checksum is calculated as follows:
			//
			// Since this is CD-DA audio, a block (sector) is 2352 bytes in size and 1/75th of a second in duration
			// A single 2352 byte block contains 588 audio frames at 16 bits per channel and 2 channels
			//
			// For checksum calculations, AccurateRip treats a single audio frame of as a 32-bit quantity
			// This is bad, because math overflow can lead to discarded samples (bits) from the right channel
			//
			// Multiply the audio frame's value (as an (unsigned?) 32-bit integer) [f(n)] times it's frame number [n]
			// The first four blocks and 587 frames of the first track are skipped (zero checksum value)
			// The last six blocks of the last track are skipped (zero checksum value)
			//
			// The checksum is additive
			
			uint32_t arTrackChecksum = 0;
			[accurateRipResponseData getBytes:&arTrackChecksum range:NSMakeRange(trackDataOffset + 1, 4)];
			arTrackChecksum = OSSwapLittleToHostInt32(arTrackChecksum);
			
			uint32_t arOffsetChecksum = 0;
			[accurateRipResponseData getBytes:&arOffsetChecksum range:NSMakeRange(trackDataOffset + 1 + 4, 4)];
			arOffsetChecksum = OSSwapLittleToHostInt32(arOffsetChecksum);

			trackDataOffset += (1 + 4 + 4);
			
			// Don't add tracks with no information
			if(!arTrackConfidence && !arTrackChecksum && !arOffsetChecksum)
				continue;
			
			// Add the AccurateRipTrackRecord to the AccurateRipDiscRecord
			AccurateRipTrackRecord *accurateRipTrack = [NSEntityDescription insertNewObjectForEntityForName:@"AccurateRipTrackRecord" 
																					 inManagedObjectContext:accurateRipDisc.managedObjectContext];	
				
			accurateRipTrack.number = [NSNumber numberWithUnsignedInteger:(1 + i)];
			[accurateRipDisc addTracksObject:accurateRipTrack];
			
			if(arTrackConfidence)
				accurateRipTrack.confidenceLevel = [NSNumber numberWithUnsignedChar:arTrackConfidence];

			// Since Core Data only stores signed integers, cast the unsigned checksum to signed for storage
			if(arTrackChecksum)
				accurateRipTrack.checksum = [NSNumber numberWithInt:(int32_t)arTrackChecksum];
			
			if(arOffsetChecksum)
				accurateRipTrack.offsetChecksum = [NSNumber numberWithInt:(int32_t)arOffsetChecksum];
		}
		
		pressingDataOffset += accurateRipDiscDataSize;
	}
	
	// Save the changes
	if(managedObjectContext.hasChanges) {
		if(![managedObjectContext save:&error])
			self.error = error;
	}
}

@end
