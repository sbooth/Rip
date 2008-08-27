/*
 *  Copyright (C) 2005 - 2007 Stephen F. Booth <me@sbooth.org>
 *  All Rights Reserved
 */

#import "CompactDisc.h"

#import "SectorRange.h"
#import "SessionDescriptor.h"
#import "TrackDescriptor.h"

#include <discid/discid.h>
#include <IOKit/storage/IOCDMedia.h>

// ========================================
// Calculates the sum of the digits in the given number
static NSInteger sum_digits(NSInteger number)
{ 
	NSInteger sum = 0; 
	
	while(0 < number) { 
		sum += (number % 10); 
		number /= 10; 
	}
	
	return sum;
}

// ========================================
// Calculate the FreeDB ID for the given CDTOC
static NSInteger calculateFreeDBDiscIDForCDTOC(CDTOC *toc)
{
	NSCParameterAssert(NULL != toc);

	NSInteger sumOfTrackLengthDigits = 0;
	NSUInteger firstTrackNumber = 0, lastTrackNumber = 0;
	CDMSF leadOutMSF = { 0, 0, 0 };

	// Iterate through each descriptor and extract the information we need
	// For multi-session discs only the first session is used to generate the FreeDB ID
	NSUInteger numDescriptors = CDTOCGetDescriptorCount(toc);
	NSUInteger i;
	for(i = 0; i < numDescriptors; ++i) {
		CDTOCDescriptor *desc = &toc->descriptors[i];
		
		// First track
		if(0xA0 == desc->point && 1 == desc->adr) {
			if(1 == desc->session)
				firstTrackNumber = desc->p.minute;
		}
		// Last track
		else if(0xA1 == desc->point && 1 == desc->adr) {
			if(1 == desc->session)
				lastTrackNumber = desc->p.minute;
		}
		// Lead-out
		else if(0xA2 == desc->point && 1 == desc->adr) {
			if(1 == desc->session)
				leadOutMSF = desc->p;
		}
	}
	
	NSUInteger trackNumber;
	for(trackNumber = firstTrackNumber; trackNumber <= lastTrackNumber; ++trackNumber) {
		CDMSF msf = CDConvertTrackNumberToMSF(trackNumber, toc);
		sumOfTrackLengthDigits += sum_digits((msf.minute * 60) + msf.second);
	}
		
	CDMSF firstTrackMSF = CDConvertTrackNumberToMSF(firstTrackNumber, toc);
	NSInteger discLengthInSeconds = ((leadOutMSF.minute * 60) + leadOutMSF.second) - ((firstTrackMSF.minute * 60) + firstTrackMSF.second);
	
	return ((sumOfTrackLengthDigits % 0xFF) << 24 | discLengthInSeconds << 8 | (lastTrackNumber - firstTrackNumber + 1));
}

// ========================================
// Private methods
@interface CompactDisc (Private)
- (void) parseTOC:(CDTOC *)toc;
@end

@implementation CompactDisc

// ========================================
// Creation
+ (id) compactDiscWithDADiskRef:(DADiskRef)disk inManagedObjectContext:(NSManagedObjectContext *)managedObjectContext
{
	NSParameterAssert(NULL != disk);
	NSParameterAssert(nil != managedObjectContext);
	
	// Obtain the IOMedia object (it should be IOCDMedia) from the DADiskRef
	io_service_t ioMedia = DADiskCopyIOMedia(disk);
	if(IO_OBJECT_NULL == ioMedia) {
		NSLog(@"Unable to create io_service_t for DADiskRef");
		
		return nil;
	}
	
	// Get the CD's property dictionary
	CFMutableDictionaryRef mediaDictionary = NULL;
	IOReturn err = IORegistryEntryCreateCFProperties(ioMedia, &mediaDictionary, kCFAllocatorDefault, 0);
	if(kIOReturnSuccess != err) {
		NSLog(@"Unable to get properties for media (IORegistryEntryCreateCFProperties returned 0x%.8x)", err);
		
		CFRelease(mediaDictionary);
		IOObjectRelease(ioMedia);
		
		return nil;
	}
	
	// Extract the disc's TOC data, and map it to a CDTOC struct
	CFDataRef tocData = CFDictionaryGetValue(mediaDictionary, CFSTR(kIOCDMediaTOCKey));
	if(NULL == tocData) {
		NSLog(@"No value for kIOCDMediaTOCKey in IOCDMedia object");
		
		CFRelease(mediaDictionary);
		IOObjectRelease(ioMedia);
		
		return nil;
	}
	
	CompactDisc *compactDisc = [CompactDisc compactDiscWithCDTOC:(NSData *)tocData inManagedObjectContext:managedObjectContext];
	
	CFRelease(mediaDictionary);
	IOObjectRelease(ioMedia);
	
	return compactDisc;
}

+ (id) compactDiscWithCDTOC:(NSData *)tocData inManagedObjectContext:(NSManagedObjectContext *)managedObjectContext
{
	NSParameterAssert(nil != tocData);
	NSParameterAssert(nil != managedObjectContext);
	
	CDTOC *toc = (CDTOC *)[tocData bytes];
	
	// If this disc has been seen before, fetch it
	NSInteger discID = calculateFreeDBDiscIDForCDTOC(toc);

	// Build and execute a fetch request matching on the disc's FreeDB ID
	NSEntityDescription *entityDescription = [NSEntityDescription entityForName:@"CompactDisc" 
														 inManagedObjectContext:managedObjectContext];
	NSFetchRequest *fetchRequest = [[NSFetchRequest alloc] init];
	[fetchRequest setEntity:entityDescription];
	[fetchRequest setFetchLimit:1];

	NSPredicate *fetchPredicate = [NSPredicate predicateWithFormat:@"freeDBDiscID == %i", discID];
	[fetchRequest setPredicate:fetchPredicate];
	
	NSError *error = nil;
	NSArray *matchingDiscs = [managedObjectContext executeFetchRequest:fetchRequest error:&error];
	if(!matchingDiscs) {
		// TODO: Deal with error...
		[[NSApplication sharedApplication] presentError:error];
		
		return nil;
	}
	
	CompactDisc *compactDisc = nil;
	if(0 == matchingDiscs.count) {
		compactDisc = [NSEntityDescription insertNewObjectForEntityForName:@"CompactDisc"
													inManagedObjectContext:managedObjectContext];
		
		compactDisc.discTOC = tocData;
		compactDisc.freeDBDiscID = [NSNumber numberWithInteger:discID];
		[compactDisc parseTOC:toc];
	}
	else
		compactDisc = matchingDiscs.lastObject;
	
	return compactDisc;
}

// ========================================
// Core Data properties
@dynamic discTOC;
@dynamic freeDBDiscID;

// ========================================
// Core Data relationships
@dynamic accurateRipDisc;
@dynamic metadata;
@dynamic sessions;

- (void) awakeFromInsert
{
	// Create the metadata relationship
	self.metadata = [NSEntityDescription insertNewObjectForEntityForName:@"AlbumMetadata"
												  inManagedObjectContext:self.managedObjectContext];	
}

// ========================================
// Other properties
- (NSArray *) orderedSessions
{
	NSSortDescriptor *sessionNumberSortDescriptor = [[NSSortDescriptor alloc] initWithKey:@"number" ascending:YES];
	return [self.sessions.allObjects sortedArrayUsingDescriptors:[NSArray arrayWithObject:sessionNumberSortDescriptor]];
}

- (SessionDescriptor *) firstSession
{
	NSArray *orderedSessions = self.orderedSessions;
	return (0 == orderedSessions.count ? nil : [orderedSessions objectAtIndex:0]);
}

- (SessionDescriptor *) lastSession
{
	NSArray *orderedSessions = self.orderedSessions;
	return (0 == orderedSessions.count ? nil : orderedSessions.lastObject);
}

// ========================================
// Computed properties
- (NSString *) musicBrainzDiscID
{
	NSString *musicBrainzDiscID = nil;
	
	DiscId *discID = discid_new();
	if(NULL == discID)
		return nil;
	
	// For multi-session discs only the first session is used to calculate the MusicBrainz disc ID
	SessionDescriptor *firstSession = self.firstSession;
	if(!firstSession)
		return nil;
	
	// zero is lead out
	int offsets[100];
	offsets[0] = firstSession.leadOut.unsignedIntValue + 150;
	
	for(TrackDescriptor *trackDescriptor in firstSession.tracks)
		offsets[trackDescriptor.number.unsignedIntegerValue] = trackDescriptor.firstSector.unsignedIntValue + 150;
	
	int result = discid_put(discID, firstSession.firstTrack.number.unsignedIntValue, firstSession.lastTrack.number.unsignedIntValue, offsets);
	if(result)
		musicBrainzDiscID = [NSString stringWithCString:discid_get_id(discID) encoding:NSASCIIStringEncoding];
	
	discid_free(discID);
	
	return musicBrainzDiscID;
}

- (NSNumber *) accurateRipID1
{
	// ID 1 is the sum of all the disc's offsets
	// The lead out is treated as track n + 1, where n is the number of audio tracks
	NSUInteger accurateRipID1 = 0;
	
	// Use the first session
	SessionDescriptor *firstSession = self.firstSession;
	if(!firstSession)
		return nil;

	NSSet *tracks = firstSession.tracks;
	for(TrackDescriptor *track in tracks)
		accurateRipID1 += track.firstSector.unsignedIntegerValue;
	
	// Adjust for lead out
	accurateRipID1 += firstSession.leadOut.unsignedIntegerValue;
	
	return [NSNumber numberWithUnsignedInteger:accurateRipID1];
}

- (NSNumber *) accurateRipID2
{
	// ID 2 is the sum of all the disc's offsets times their track number
	// The lead out is treated as track n + 1, where n is the number of audio tracks
	NSUInteger accurateRipID2 = 0;

	// Use the first session
	SessionDescriptor *firstSession = self.firstSession;
	if(!firstSession)
		return nil;

	NSSet *tracks = firstSession.tracks;
	for(TrackDescriptor *track in tracks) {
		NSUInteger offset = track.firstSector.unsignedIntegerValue;
		accurateRipID2 += (0 == offset ? 1 : offset) * track.number.unsignedIntValue;
	}
	
	// Adjust for lead out
	accurateRipID2 += firstSession.leadOut.unsignedIntegerValue * (1 + tracks.count);

	return [NSNumber numberWithUnsignedInteger:accurateRipID2];
}

// Disc track information
/*- (NSUInteger) sessionContainingSector:(NSUInteger)sector
{
	return [self sessionContainingSectorRange:[SectorRange sectorRangeWithSector:sector]];
}

- (NSUInteger) sessionContainingSectorRange:(SectorRange *)sectorRange
{
	NSUInteger		session;
	NSUInteger		sessionFirstSector;
	NSUInteger		sessionLastSector;
	SectorRange		*sessionSectorRange;
	
	for(session = [self firstSession]; session <= [self lastSession]; ++session) {
		sessionFirstSector		= [self firstSectorForTrack:[self firstTrackForSession:session]];
		sessionLastSector		= [self lastSectorForTrack:[self lastTrackForSession:session]];
		
		sessionSectorRange		= [SectorRange sectorRangeWithFirstSector:sessionFirstSector lastSector:sessionLastSector];
		
		if([sessionSectorRange containsSectorRange:sectorRange])
			return session;
	}
	
	return NSNotFound;
}*/

// ========================================

- (SessionDescriptor *) sessionNumber:(NSUInteger)number
{
	for(SessionDescriptor *session in self.sessions) {
		if(session.number.unsignedIntegerValue == number)
			return session;
	}
	
	return nil;	
}

- (TrackDescriptor *) trackNumber:(NSUInteger)number
{
	for(SessionDescriptor *session in self.sessions) {
		TrackDescriptor *track = [session trackNumber:number];
		if(track)
			return track;
	}
	
	return nil;		
}

@end

@implementation CompactDisc (Private)

- (void) parseTOC:(CDTOC *)toc
{
	NSParameterAssert(NULL != toc);

	// Set up SessionDescriptor objects
	NSUInteger sessionNumber;
	for(sessionNumber = toc->sessionFirst; sessionNumber <= toc->sessionLast; ++sessionNumber) {
		SessionDescriptor *session = [NSEntityDescription insertNewObjectForEntityForName:@"SessionDescriptor"
																   inManagedObjectContext:self.managedObjectContext];

		session.number = [NSNumber numberWithUnsignedInteger:sessionNumber];
		[self addSessionsObject:session];
	}
	
	// Iterate through each descriptor and extract the information we need
	NSUInteger numDescriptors = CDTOCGetDescriptorCount(toc);
	NSUInteger i;
	for(i = 0; i < numDescriptors; ++i) {
		CDTOCDescriptor *desc = &toc->descriptors[i];
		
		// This is a normal audio or data track
		if(0x01 <= desc->point && 0x63 >= desc->point && 1 == desc->adr) {
			TrackDescriptor *track = [NSEntityDescription insertNewObjectForEntityForName:@"TrackDescriptor"
																   inManagedObjectContext:self.managedObjectContext];
			
			track.session = [self sessionNumber:desc->session];
			track.number = [NSNumber numberWithUnsignedChar:desc->point];
			track.firstSector = [NSNumber numberWithUnsignedInt:CDConvertMSFToLBA(desc->p)];
			
			switch(desc->control) {
				case 0x00:	
					track.channelsPerFrame = [NSNumber numberWithInt:2];
					track.hasPreEmphasis = [NSNumber numberWithBool:NO];
					track.digitalCopyPermitted = [NSNumber numberWithBool:NO];
					break;
				case 0x01:
					track.channelsPerFrame = [NSNumber numberWithInt:2];
					track.hasPreEmphasis = [NSNumber numberWithBool:YES];
					track.digitalCopyPermitted = [NSNumber numberWithBool:NO];
					break;
				case 0x02:
					track.channelsPerFrame = [NSNumber numberWithInt:2];
					track.hasPreEmphasis = [NSNumber numberWithBool:NO];
					track.digitalCopyPermitted = [NSNumber numberWithBool:YES];
					break;
				case 0x03:
					track.channelsPerFrame = [NSNumber numberWithInt:2];
					track.hasPreEmphasis = [NSNumber numberWithBool:YES];
					track.digitalCopyPermitted = [NSNumber numberWithBool:YES];
					break;
				case 0x04:
					track.isDataTrack = [NSNumber numberWithBool:YES];
					track.digitalCopyPermitted = [NSNumber numberWithBool:NO];
					break;
				case 0x06:
					track.isDataTrack = [NSNumber numberWithBool:YES];
					track.digitalCopyPermitted = [NSNumber numberWithBool:YES];
					break;
				case 0x08:
					track.channelsPerFrame = [NSNumber numberWithInt:4];
					track.hasPreEmphasis = [NSNumber numberWithBool:NO];
					track.digitalCopyPermitted = [NSNumber numberWithBool:NO];
					break;
				case 0x09:
					track.channelsPerFrame = [NSNumber numberWithInt:4];
					track.hasPreEmphasis = [NSNumber numberWithBool:YES];
					track.digitalCopyPermitted = [NSNumber numberWithBool:NO];
					break;
				case 0x0A:
					track.channelsPerFrame = [NSNumber numberWithInt:4];
					track.hasPreEmphasis = [NSNumber numberWithBool:NO];
					track.digitalCopyPermitted = [NSNumber numberWithBool:YES];
					break;
				case 0x0B:
					track.channelsPerFrame = [NSNumber numberWithInt:4];
					track.hasPreEmphasis = [NSNumber numberWithBool:NO];
					track.digitalCopyPermitted = [NSNumber numberWithBool:YES];
					break;
			}			
		}
		else if(0xA0 == desc->point && 1 == desc->adr) {
			;//[[self sessionNumber:desc->session] setFirstTrack:desc->p.minute];
/*			NSLog(@"Disc type:                 %d (%s)\n", (int)desc->p.second,
				  (0x00 == desc->p.second) ? "CD-DA, or CD-ROM with first track in Mode 1":
				  (0x10 == desc->p.second) ? "CD-I disc":
				  (0x20 == desc->p.second) ? "CD-ROM XA disc with first track in Mode 2" : "Unknown");*/
		}
		// Last track
		else if(0xA1 == desc->point && 1 == desc->adr)
			;//[[self sessionNumber:desc->session] setLastTrack:desc->p.minute];
		// Lead-out
		else if(0xA2 == desc->point && 1 == desc->adr)
			[self sessionNumber:desc->session].leadOut = [NSNumber numberWithUnsignedInt:CDConvertMSFToLBA(desc->p)];
/*		else if(0xB0 == desc->point && 5 == desc->adr) {
			NSLog(@"Next possible track start: %02d:%02d.%02d\n",
				  (int)desc->address.minute, (int)desc->address.second, (int)desc->address.frame);
			NSLog(@"Number of ptrs in Mode 5:  %d\n",
				  (int)desc->zero);
			NSLog(@"Last possible lead-out:    %02d:%02d.%02d\n",
				  (int)desc->p.minute, (int)desc->p.second, (int)desc->p.frame);
		}
		else if(0xB1 == desc->point && 5 == desc->adr) {
			NSLog(@"Skip interval pointers:    %d\n", (int)desc->p.minute);
			NSLog(@"Skip track pointers:       %d\n", (int)desc->p.second);
		}
		else if(0xB2 <= desc->point && 0xB2 >= desc->point && 5 == desc->adr) {
			NSLog(@"Skip numbers:              %d, %d, %d, %d, %d, %d, %d\n",
				  (int)desc->address.minute, (int)desc->address.second, (int)desc->address.frame,
				  (int)desc->zero, (int)desc->p.minute, (int)desc->p.second, (int)desc->p.frame);
		}
		else if(1 == desc->point && 40 >= desc->point && 5 == desc->adr) {
			NSLog(@"Skip from %02d:%02d.%02d to %02d:%02d.%02d\n",
				  (int)desc->p.minute, (int)desc->p.second, (int)desc->p.frame,
				  (int)desc->address.minute, (int)desc->address.second, (int)desc->address.frame);
		}
		else if(0xC0 == desc->point && 5 == desc->adr) {
			NSLog(@"Optimum recording power:   %d\n", (int)desc->address.minute);
			NSLog(@"Application code:          %d\n", (int)desc->address.second);
			NSLog(@"Start of first lead-in:    %02d:%02d.%02d\n",
				  (int)desc->p.minute, (int)desc->p.second, (int)desc->p.frame);
		}*/
	}
	
	// Make one pass over the parsed tracks and fill in the last sector for each
	SessionDescriptor *firstSession = self.firstSession;
	for(TrackDescriptor *track in firstSession.tracks) {
		TrackDescriptor *nextTrack = [firstSession trackNumber:(1 + track.number.unsignedIntegerValue)];
		if(nil != nextTrack)
			track.lastSector = [NSNumber numberWithUnsignedInteger:(nextTrack.firstSector.unsignedIntegerValue - 1)];
		else
			track.lastSector = [NSNumber numberWithUnsignedInteger:(firstSession.leadOut.unsignedIntegerValue - 1)];		
	}
}

@end
