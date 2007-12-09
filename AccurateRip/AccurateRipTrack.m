/*
 *  Copyright (C) 2007 Stephen F. Booth <me@sbooth.org>
 *  All Rights Reserved
 */

#import "AccurateRipTrack.h"

// Public getters, private setters
@interface AccurateRipTrack ()
@property (assign) NSUInteger number;
@property (assign) uint8_t confidenceLevel;
@property (assign) uint32_t CRC;
@end

@implementation AccurateRipTrack

@synthesize number = _number;
@synthesize confidenceLevel = _confidenceLevel;
@synthesize CRC = _CRC;

+ (id) trackForTrack:(NSUInteger)number confidenceLevel:(uint8_t)confidenceLevel CRC:(uint32_t)CRC
{
	return [[AccurateRipTrack alloc] initWithNumber:number confidenceLevel:confidenceLevel CRC:CRC];
}

- (id) initWithNumber:(NSUInteger)number confidenceLevel:(uint8_t)confidenceLevel CRC:(uint32_t)CRC;
{
	if((self = [super init])) {
		self.number = number;
		self.confidenceLevel = confidenceLevel;
		self.CRC = CRC;
	}
	return self;
}

- (id) copyWithZone:(NSZone *)zone
{
	AccurateRipTrack *copy = [[[self class] allocWithZone:zone] init];
	
	copy.number = self.number;
	copy.confidenceLevel = self.confidenceLevel;
	copy.CRC = self.CRC;
	
	return copy;
}

@end
