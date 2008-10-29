/*
 *  Copyright (C) 2005 - 2008 Stephen F. Booth <me@sbooth.org>
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
static NSUInteger calculateFreeDBDiscIDForCDTOC(CDTOC *toc)
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
		
		// For multi-session discs only the first session is used to generate the FreeDB ID
		if(1 != desc->session)
			continue;

		// First track
		if(0xA0 == desc->point && 1 == desc->adr)
			firstTrackNumber = desc->p.minute;
		// Last track
		else if(0xA1 == desc->point && 1 == desc->adr)
			lastTrackNumber = desc->p.minute;
		// Lead-out
		else if(0xA2 == desc->point && 1 == desc->adr)
			leadOutMSF = desc->p;
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
// Calculate the MusicBrainz ID for the given CDTOC
static NSString * calculateMusicBrainzDiscIDForCDTOC(CDTOC *toc)
{
	NSCParameterAssert(NULL != toc);

	NSString *musicBrainzDiscID = nil;
	
	DiscId *discID = discid_new();
	if(NULL == discID)
		return nil;
	
	int offsets[100];
	int firstTrackNumber = 0, lastTrackNumber = 0;
	
	// Non-existent tracks are treated as zeroes
	memset(offsets, 0, 100 * sizeof(int));

	// Iterate through each descriptor and extract the information we need
	NSUInteger numDescriptors = CDTOCGetDescriptorCount(toc);
	NSUInteger i;
	for(i = 0; i < numDescriptors; ++i) {
		CDTOCDescriptor *desc = &toc->descriptors[i];

		// For multi-session discs only the first session is used to generate the MusicBrainz ID
		if(1 != desc->session)
			continue;

		// This is a normal audio or data track
		if(0x01 <= desc->point && 0x63 >= desc->point && 1 == desc->adr)
				offsets[desc->point] = CDConvertMSFToLBA(desc->p) + 150;
		// First track
		else if(0xA0 == desc->point && 1 == desc->adr)
				firstTrackNumber = desc->p.minute;
		// Last track
		else if(0xA1 == desc->point && 1 == desc->adr)
				lastTrackNumber = desc->p.minute;
		// Lead-out
		else if(0xA2 == desc->point && 1 == desc->adr)
				offsets[0] = CDConvertMSFToLBA(desc->p) + 150;
	}

	int result = discid_put(discID, firstTrackNumber, lastTrackNumber, offsets);
	if(result)
		musicBrainzDiscID = [NSString stringWithCString:discid_get_id(discID) encoding:NSASCIIStringEncoding];
	
	discid_free(discID);

	return musicBrainzDiscID;
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
	NSString *discID = calculateMusicBrainzDiscIDForCDTOC(toc);

	// Build and execute a fetch request matching on the disc's MusicBrainz ID
	NSEntityDescription *entityDescription = [NSEntityDescription entityForName:@"CompactDisc" 
														 inManagedObjectContext:managedObjectContext];
	NSFetchRequest *fetchRequest = [[NSFetchRequest alloc] init];
	[fetchRequest setEntity:entityDescription];
	[fetchRequest setFetchLimit:1];

	NSPredicate *fetchPredicate = [NSPredicate predicateWithFormat:@"musicBrainzDiscID == %@", discID];
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
		compactDisc.musicBrainzDiscID = discID;
		[compactDisc parseTOC:toc];
	}
	else
		compactDisc = matchingDiscs.lastObject;
	
	return compactDisc;
}

// ========================================
// Key dependencies
+ (NSSet *) keyPathsForValuesAffectingOrderedSessions
{
	return [NSSet setWithObject:@"sessions"];
}

+ (NSSet *) keyPathsForValuesAffectingFirstSession
{
	return [NSSet setWithObject:@"sessions"];
}

+ (NSSet *) keyPathsForValuesAffectingLastSession
{
	return [NSSet setWithObject:@"sessions"];
}

// ========================================
// Core Data properties
@dynamic discTOC;
@dynamic musicBrainzDiscID;

// ========================================
// Core Data relationships
@dynamic accurateRipDiscs;
@dynamic extractedImages;
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
- (NSUInteger) freeDBDiscID
{
	CDTOC *toc = (CDTOC *)[self.discTOC bytes];
	return calculateFreeDBDiscIDForCDTOC(toc);
}

- (NSUInteger) accurateRipID1
{
	// ID 1 is the sum of all the disc's offsets
	// The lead out is treated as track n + 1, where n is the number of audio tracks
	NSUInteger accurateRipID1 = 0;
	
	// Use the first session
	SessionDescriptor *firstSession = self.firstSession;
	if(!firstSession)
		return 0;

	for(TrackDescriptor *track in firstSession.tracks)
		accurateRipID1 += track.firstSector.unsignedIntegerValue;
	
	// Adjust for lead out
	accurateRipID1 += firstSession.leadOut.unsignedIntegerValue;
	
	return accurateRipID1;
}

- (NSUInteger) accurateRipID2
{
	// ID 2 is the sum of all the disc's offsets times their track number
	// The lead out is treated as track n + 1, where n is the number of audio tracks
	NSUInteger accurateRipID2 = 0;

	// Use the first session
	SessionDescriptor *firstSession = self.firstSession;
	if(!firstSession)
		return 0;

	NSSet *tracks = firstSession.tracks;
	for(TrackDescriptor *track in tracks) {
		NSUInteger offset = track.firstSector.unsignedIntegerValue;
		accurateRipID2 += (0 == offset ? 1 : offset) * track.number.unsignedIntValue;
	}
	
	// Adjust for lead out
	accurateRipID2 += firstSession.leadOut.unsignedIntegerValue * (1 + tracks.count);

	return accurateRipID2;
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
		// First track in session
		else if(0xA0 == desc->point && 1 == desc->adr)
			;//[[self sessionNumber:desc->session] setFirstTrack:desc->p.minute];
		// Last track in session
		else if(0xA1 == desc->point && 1 == desc->adr)
			;//[[self sessionNumber:desc->session] setLastTrack:desc->p.minute];
		// Lead-out
		else if(0xA2 == desc->point && 1 == desc->adr)
			[self sessionNumber:desc->session].leadOut = [NSNumber numberWithUnsignedInt:CDConvertMSFToLBA(desc->p)];
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
