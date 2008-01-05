/*
 *  Copyright (C) 2007 Stephen F. Booth <me@sbooth.org>
 *  All Rights Reserved
 */

#import "AccurateRipDisc.h"
#import "CompactDisc.h"
#import "TrackDescriptor.h"
#import "AccurateRipTrack.h"

@interface AccurateRipDisc ()
@property (assign) CompactDisc * compactDisc;
@property (assign) BOOL discFound;
@property (copy) NSError * error;
@property (assign) NSUInteger accurateRipID1;
@property (assign) NSUInteger accurateRipID2;
@property (assign) NSURLConnection * connection;
@property (assign) NSMutableData * responseData;
@end

@interface AccurateRipDisc (Private)
- (void) calculateDiscIDs;
- (void) parseAccurateRipResponse;
@end

@implementation AccurateRipDisc

@synthesize compactDisc = _compactDisc;
@synthesize discFound = _discFound;
@synthesize error = _error;
@synthesize accurateRipID1 = _accurateRipID1;
@synthesize accurateRipID2 = _accurateRipID2;
@synthesize tracks = _tracks;
@synthesize connection = _connection;
@synthesize responseData = _responseData;

- (id) initWithCompactDisc:(CompactDisc *)compactDisc
{
	NSParameterAssert(nil != compactDisc);
	
	if((self = [super init])) {
		self.compactDisc = compactDisc;
		[self calculateDiscIDs];
	}
	return self;
}

- (id) copyWithZone:(NSZone *)zone
{
	AccurateRipDisc *copy = [[[self class] allocWithZone:zone] init];

	copy.compactDisc = self.compactDisc;
	copy->_tracks = [_tracks mutableCopy];
	copy.accurateRipID1 = self.accurateRipID1;
	copy.accurateRipID2 = self.accurateRipID2;
	
	return copy;
}

- (IBAction) performAccurateRipQuery:(id)sender
{
	
#pragma unused(sender)
	
	NSUInteger discID1 = self.accurateRipID1;
	NSUInteger discID2 = self.accurateRipID2;
	
	// Use the first session
	NSArray *sessionTracks = [self.compactDisc tracksForSession:1];

	// Build the URL
	NSURL *accurateRipURL = [NSURL URLWithString:[NSString stringWithFormat:@"http://www.accuraterip.com/accuraterip/%.1x/%.1x/%.1x/dBAR-%.3d-%.8x-%.8x-%.8x.bin",
												  discID1 & 0x0F,
												  (discID1 >> 4) & 0x0F,
												  (discID1 >> 8) & 0x0F,
												  sessionTracks.count,
												  discID1,
												  discID2,
												  self.compactDisc.freeDBDiscID]];
	
	// Create a request for the URL with a 1 minute timeout
	NSURLRequest *request = [NSURLRequest requestWithURL:accurateRipURL
											 cachePolicy:NSURLRequestUseProtocolCachePolicy
										 timeoutInterval:60.0];
	
	if(self.connection)
		[self.connection cancel];
	
	self.error = nil;
	self.responseData = nil;
	
	// Create the connection with the request and start loading the data
	self.connection = [NSURLConnection connectionWithRequest:request delegate:self];
	if(self.connection)
		self.responseData = [[NSMutableData alloc] init];
	else {
#if DEBUG
		NSLog(@"Unable to establish connection to %@", accurateRipURL);
#endif
		
		self.error = [NSError errorWithDomain:NSPOSIXErrorDomain code:ENOMEM userInfo:nil];
	}		
}

- (AccurateRipTrack *) trackNumber:(NSUInteger)trackNumber
{
	for(AccurateRipTrack *track in _tracks) {
		if(trackNumber == track.number)
			return track;
	}
	return nil;
}

#pragma mark KVC Accessors for tracks

- (NSUInteger) countOfTracks
{
	return [_tracks count];
}

- (AccurateRipTrack *) objectInTracksAtIndex:(NSUInteger)index
{
	return [_tracks objectAtIndex:index];
}

- (void) getTracks:(id *)buffer range:(NSRange)range
{
	[_tracks getObjects:buffer range:range];
}

#pragma mark NSURLConnection Delegate Methods

- (void) connection:(NSURLConnection *)connection didReceiveResponse:(NSURLResponse *)response
{
	
#pragma unused(connection)
#pragma unused(response)
	
	[self.responseData setLength:0];
}

- (void) connection:(NSURLConnection *)connection didReceiveData:(NSData *)data
{
	
#pragma unused(connection)
	
	[self.responseData appendData:data];
}

- (void) connection:(NSURLConnection *)connection didFailWithError:(NSError *)error
{
	
#pragma unused(connection)
	
	self.connection = nil;
	self.responseData = nil;

#if DEBUG
	NSLog(@"Connection to AccurateRip failed: %@ %@", [error localizedDescription], [[error userInfo] objectForKey:NSErrorFailingURLStringKey]);
#endif
	
	self.error = error;	
}

- (void) connectionDidFinishLoading:(NSURLConnection *)connection
{

#pragma unused(connection)

	self.connection = nil;
	
	[self parseAccurateRipResponse];
}

@end

@implementation AccurateRipDisc (Private)

- (void) calculateDiscIDs
{
	// Calculate the disc IDs used by Accurate Rip
	// ID 1 is the sum of all the disc's offsets
	// ID 2 is the sum of all the disc's offsets times their track number
	// The lead out is treated as track n + 1, where n is the number of audio tracks
	// ID 3 is the CDDB/FreeDB disc ID
	NSUInteger discID1 = 0, discID2 = 0;
	
	// Use the first session
	NSArray *sessionTracks = [self.compactDisc tracksForSession:1];
	for(TrackDescriptor *track in sessionTracks) {
		NSUInteger offset = track.firstSector;
		discID1 += offset;
		discID2 += (0 == offset ? 1 : offset) * track.number;
	}
	
	// Adjust for lead out
	NSUInteger leadOut = [self.compactDisc leadOutForSession:1];
	discID1 += leadOut;
	discID2 += leadOut * (1 + sessionTracks.count);
	
	// Save the disc IDs for later
	self.accurateRipID1 = discID1;
	self.accurateRipID2 = discID2;	
}

- (void) parseAccurateRipResponse
{
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
	NSArray *sessionTracks = [self.compactDisc tracksForSession:1];

	uint8_t arTrackCount = 0;
	[self.responseData getBytes:&arTrackCount range:NSMakeRange(0, 1)];
	
	uint32_t arDiscID1 = 0;
	[self.responseData getBytes:&arDiscID1 range:NSMakeRange(1, 4)];
	arDiscID1 = OSSwapLittleToHostInt32(arDiscID1);
	
	uint32_t arDiscID2 = 0;
	[self.responseData getBytes:&arDiscID2 range:NSMakeRange(5, 4)];
	arDiscID2 = OSSwapLittleToHostInt32(arDiscID2);
	
	int32_t arFreeDBID = 0;
	[self.responseData getBytes:&arFreeDBID range:NSMakeRange(9, 4)];
	arFreeDBID = OSSwapLittleToHostInt32(arFreeDBID);
	
	if(arTrackCount != sessionTracks.count || arDiscID1 != self.accurateRipID1 || arDiscID2 != self.accurateRipID2 || arFreeDBID != self.compactDisc.freeDBDiscID) {
		NSLog(@"AccurateRip track count or disc IDs don't match.");
		return;
	}
	
	[self willChangeValueForKey:@"tracks"];
	_tracks = [[NSMutableArray alloc] init];
	
	NSUInteger i, offset = 13;
	for(i = 0; i < arTrackCount; ++i) {
		uint8_t arTrackConfidence = 0;
		[self.responseData getBytes:&arTrackConfidence range:NSMakeRange(offset, 1)];
		
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
		[self.responseData getBytes:&arTrackCRC range:NSMakeRange(offset + 1, 4)];
		arTrackCRC = OSSwapLittleToHostInt32(arTrackCRC);
		
/*		uint32_t arTrackStartCRC = 0;
		[self.responseData getBytes:&arTrackStartCRC range:NSMakeRange(offset + 1 + 4, 4)];
		arTrackStartCRC = OSSwapLittleToHostInt32(arTrackStartCRC);*/
		
		// What are the next 4 bytes?
		
		offset += 9;
		
		AccurateRipTrack *track = [[AccurateRipTrack alloc] initWithNumber:(1 + i) confidenceLevel:arTrackConfidence CRC:arTrackCRC];
		[_tracks addObject:track];
	}
	
	[self didChangeValueForKey:@"tracks"];
	
	self.responseData = nil;
	self.discFound = (0 != self.tracks.count);
}

@end
