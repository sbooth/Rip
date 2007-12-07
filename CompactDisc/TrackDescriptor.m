/*
 *  $Id$
 *  Copyright (C) 2005 - 2007 Stephen F. Booth <me@sbooth.org>
 *  All Rights Reserved
 */

#import "TrackDescriptor.h"

@implementation TrackDescriptor

@synthesize session = _session;
@synthesize number = _number;
@synthesize firstSector = _firstSector;
@synthesize channels = _channels;
@synthesize preEmphasis = _preEmphasis;
@synthesize copyPermitted = _copyPermitted;
@synthesize dataTrack = _dataTrack;

- (id) copyWithZone:(NSZone *)zone
{
	TrackDescriptor *copy = [[[self class] allocWithZone:zone] init];
	
	copy.session = self.session;
	copy.number = self.number;
	copy.firstSector = self.firstSector;
	copy.channels = self.channels;
	copy.preEmphasis = self.preEmphasis;
	copy.copyPermitted = self.copyPermitted;
	copy.dataTrack = self.dataTrack;
	
	return copy;
}

- (NSString *) description
{
	return [NSString stringWithFormat:@"TrackDescriptor {\n\tSession: %u\n\tTrack: %u\n\tFirst Sector: %i\n}", self.session, self.number, self.firstSector];
}

@end

