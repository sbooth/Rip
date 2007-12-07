/*
 *  $Id$
 *  Copyright (C) 2005 - 2007 Stephen F. Booth <me@sbooth.org>
 *  All Rights Reserved
 */

#import "SessionDescriptor.h"

@implementation SessionDescriptor

@synthesize number = _number;
@synthesize firstTrack = _firstTrack;
@synthesize lastTrack = _lastTrack;
@synthesize leadOut = _leadOut;

- (id) copyWithZone:(NSZone *)zone
{
	SessionDescriptor *copy = [[[self class] allocWithZone:zone] init];

	copy.number = self.number;
	copy.firstTrack = self.firstTrack;
	copy.lastTrack = self.lastTrack;
	copy.leadOut = self.leadOut;

	return copy;
}

- (NSString *) description
{
	return [NSString stringWithFormat:@"SessionDescriptor {\n\tSession: %u\n\tFirst Track: %u\n\tLast Track: %u\n\tLead Out: %u\n}", self.number, self.firstTrack, self.lastTrack, self.leadOut];
}

@end
