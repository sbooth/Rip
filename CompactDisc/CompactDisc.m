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
static NSInteger
sum_digits(NSInteger number)
{ 
	NSInteger sum = 0; 
	
	while(0 < number) { 
		sum += (number % 10); 
		number /= 10; 
	}
	
	return sum;
}

// ========================================
// Public getters, private setters
@interface CompactDisc ()
@property (assign) NSUInteger firstSession;
@property (assign) NSUInteger lastSession;
@end

// ========================================
// Private methods
@interface CompactDisc (Private)
- (void) parseTOC:(CDTOC *)toc;
@end

@implementation CompactDisc

@synthesize firstSession = _firstSession;
@synthesize lastSession = _lastSession;
@synthesize sessions = _sessions;
@synthesize tracks = _tracks;

- (id) initWithDADiskRef:(DADiskRef)disk
{
	NSParameterAssert(NULL != disk);
	
	if((self = [super init])) {
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
		
		CDTOC *toc = (CDTOC *)CFDataGetBytePtr(tocData);
		[self parseTOC:toc];
		
		CFRelease(mediaDictionary);
		IOObjectRelease(ioMedia);
	}
	return self;
}

- (id) initWithCDTOC:(CDTOC *)toc
{
	NSParameterAssert(NULL != toc);
	
	if((self = [super init]))
		[self parseTOC:toc];
	return self;
}

- (id) copyWithZone:(NSZone *)zone
{
	CompactDisc *copy = [[[self class] allocWithZone:zone] init];
	
	copy->_sessions = [_sessions mutableCopy];
	copy->_tracks = [_tracks mutableCopy];
	copy.firstSession = self.firstSession;
	copy.lastSession = self.lastSession;
	
	return copy;
}

- (NSInteger) freeDBDiscID
{
	NSInteger sumOfTrackLengthDigits = 0;
	
	// For multi-session discs only the first session is used to generate the FreeDB ID
	SessionDescriptor *session = [self sessionNumber:1];
	
	NSUInteger trackNumber;
	for(trackNumber = session.firstTrack; trackNumber <= session.lastTrack; ++trackNumber) {
		CDMSF msf = CDConvertLBAToMSF([self trackNumber:trackNumber].firstSector);
		sumOfTrackLengthDigits += sum_digits((msf.minute * 60) + msf.second);
	}

	CDMSF firstTrack = CDConvertLBAToMSF([self trackNumber:session.firstTrack].firstSector);
	CDMSF leadOut = CDConvertLBAToMSF(session.leadOut);
	NSInteger discLengthInSeconds = ((leadOut.minute * 60) + leadOut.second) - ((firstTrack.minute * 60) + firstTrack.second);
	
	return ((sumOfTrackLengthDigits % 0xFF) << 24 | discLengthInSeconds << 8 | (session.lastTrack - session.firstTrack + 1));
}

- (NSString *) musicBrainzDiscID
{
	NSString *musicBrainzDiscID = nil;
	
	DiscId *discID = discid_new();
	if(NULL == discID)
		return nil;
	
	// zero is lead out
	int offsets[100];
	offsets[0] = [self leadOutForSession:1] + 150;
	
	NSArray *firstSessionTracks = [self tracksForSession:1];
	for(TrackDescriptor *trackDescriptor in firstSessionTracks)
		offsets[trackDescriptor.number] = trackDescriptor.firstSector + 150;
	
	int result = discid_put(discID, 1, firstSessionTracks.count, offsets);
	if(result)
		musicBrainzDiscID = [NSString stringWithCString:discid_get_id(discID) encoding:NSASCIIStringEncoding];
	
	discid_free(discID);
	
	return musicBrainzDiscID;
}

// Disc track information
- (NSUInteger) sessionContainingSector:(NSUInteger)sector
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
}

// Disc session information
- (SessionDescriptor *)	sessionNumber:(NSUInteger)number
{
	for(SessionDescriptor *session in _sessions) {
		if(session.number == number)
			return session;
	}
	
	return nil;
}

// First and last track and lead out information (session-based)
- (NSUInteger) firstTrackForSession:(NSUInteger)session			{ return [[self sessionNumber:session] firstTrack]; }
- (NSUInteger) lastTrackForSession:(NSUInteger)session			{ return [[self sessionNumber:session] lastTrack]; }
- (NSUInteger) leadOutForSession:(NSUInteger)session			{ return [[self sessionNumber:session] leadOut]; }

- (NSUInteger) firstSectorForSession:(NSUInteger)session		{ return [self firstSectorForTrack:[[self sessionNumber:session] firstTrack]]; }
- (NSUInteger) lastSectorForSession:(NSUInteger)session			{ return [[self sessionNumber:session] leadOut] - 1; }

- (TrackDescriptor *) trackNumber:(NSUInteger)number
{
	for(TrackDescriptor *track in _tracks) {
		if(track.number == number)
			return track;
	}
	
	return nil;
}

- (NSArray *) tracksForSession:(NSUInteger)session
{
	NSMutableArray *result = [[NSMutableArray alloc] init];
	
	for(TrackDescriptor *track in _tracks) {
		if(session == track.session)
			[result addObject:track];
	}

	if(0 == result.count)
		return nil;
	else
		return result;
}

// Track sector information
- (NSUInteger)			firstSectorForTrack:(NSUInteger)number		{ return [[self trackNumber:number] firstSector]; }

- (NSUInteger) lastSectorForTrack:(NSUInteger)number
{
	TrackDescriptor		*thisTrack		= [self trackNumber:number];
	TrackDescriptor		*nextTrack		= [self trackNumber:number + 1];
	
	if(nil == thisTrack)
		@throw [NSException exceptionWithName:@"IllegalArgumentException" reason:[NSString stringWithFormat:@"Track %u doesn't exist", number] userInfo:nil];
	
	return ([self lastTrackForSession:thisTrack.session] == number ? [self lastSectorForSession:thisTrack.session] : nextTrack.firstSector - 1);
}

#pragma mark KVC Accessors for sessions

- (NSUInteger) countOfSessions
{
	return [_sessions count];
}

- (SessionDescriptor *) objectInSessionsAtIndex:(NSUInteger)index
{
	return [_sessions objectAtIndex:index];
}

- (void) getSessions:(id *)buffer range:(NSRange)range
{
	[_sessions getObjects:buffer range:range];
}

#pragma mark KVC Accessors for tracks

- (NSUInteger) countOfTracks
{
	return [_tracks count];
}

- (TrackDescriptor *) objectInTracksAtIndex:(NSUInteger)index
{
	return [_tracks objectAtIndex:index];
}

- (void) getTracks:(id *)buffer range:(NSRange)range
{
	[_tracks getObjects:buffer range:range];
}

- (NSString *) description
{
	return [NSString stringWithFormat:@"{\n\tFirst Session: %u\n\tLast Session: %u\n}", self.firstSession, self.lastSession];
}

@end

@implementation CompactDisc (Private)

- (void) parseTOC:(CDTOC *)toc;
{
	NSParameterAssert(NULL != toc);
	
	_sessions = [[NSMutableArray alloc] init];
	_tracks = [[NSMutableArray alloc] init];

	NSUInteger numDescriptors = CDTOCGetDescriptorCount(toc);
	
	self.firstSession = toc->sessionFirst;
	self.lastSession = toc->sessionLast;
	
	// Set up objects that will hold first sector, last sector and lead out information for each session	
	NSUInteger i;
	for(i = self.firstSession; i <= self.lastSession; ++i) {
		SessionDescriptor *session = [[SessionDescriptor alloc] init];
		[session setNumber:i];
		[_sessions addObject:session];
	}
	
	// Iterate through each descriptor and extract the information we need
	for(i = 0; i < numDescriptors; ++i) {
		CDTOCDescriptor *desc = &toc->descriptors[i];
		
		// This is a normal audio or data track
		if(0x01 <= desc->point && 0x63 >= desc->point && 1 == desc->adr) {
			TrackDescriptor *track = [[TrackDescriptor alloc] init];
			
			[track setSession:desc->session];
			[track setNumber:desc->point];
			[track setFirstSector:CDConvertMSFToLBA(desc->p)];
			
			switch(desc->control) {
				case 0x00:	track.channels = 2;		track.preEmphasis = NO;		track.copyPermitted = NO;	break;
				case 0x01:	track.channels = 2;		track.preEmphasis = YES;	track.copyPermitted = NO;	break;
				case 0x02:	track.channels = 2;		track.preEmphasis = NO;		track.copyPermitted = YES;	break;
				case 0x03:	track.channels = 2;		track.preEmphasis = YES;	track.copyPermitted = YES;	break;
				case 0x04:	track.dataTrack = YES;								track.copyPermitted = NO;	break;
				case 0x06:	track.dataTrack = YES;								track.copyPermitted = YES;	break;
				case 0x08:	track.channels = 4;		track.preEmphasis = NO;		track.copyPermitted = NO;	break;
				case 0x09:	track.channels = 4;		track.preEmphasis = YES;	track.copyPermitted = NO;	break;
				case 0x0A:	track.channels = 4;		track.preEmphasis = NO;		track.copyPermitted = YES;	break;
				case 0x0B:	track.channels = 4;		track.preEmphasis = NO;		track.copyPermitted = YES;	break;
			}
			
			[_tracks addObject:track];
		}
		else if(0xA0 == desc->point && 1 == desc->adr) {
			[[self sessionNumber:desc->session] setFirstTrack:desc->p.minute];
/*			NSLog(@"Disc type:                 %d (%s)\n", (int)desc->p.second,
				  (0x00 == desc->p.second) ? "CD-DA, or CD-ROM with first track in Mode 1":
				  (0x10 == desc->p.second) ? "CD-I disc":
				  (0x20 == desc->p.second) ? "CD-ROM XA disc with first track in Mode 2" : "Unknown");*/
		}
		// Last track
		else if(0xA1 == desc->point && 1 == desc->adr)
			[[self sessionNumber:desc->session] setLastTrack:desc->p.minute];
		// Lead-out
		else if(0xA2 == desc->point && 1 == desc->adr)
			[[self sessionNumber:desc->session] setLeadOut:CDConvertMSFToLBA(desc->p)];
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
}

@end
