/*
 *  Copyright (C) 2007 Stephen F. Booth <me@sbooth.org>
 *  All Rights Reserved
 */

#import <Cocoa/Cocoa.h>

// ========================================
// A single track from a disc in the AccurateRip database
// ========================================
@interface AccurateRipTrack : NSObject <NSCopying>
{
	NSUInteger _number;	
	uint8_t _confidenceLevel;
	uint32_t _CRC;
//	uint32_t _CRC2;
}

@property (readonly) NSUInteger number;
@property (readonly) uint8_t confidenceLevel;
@property (readonly) uint32_t CRC;

+ (id) trackForTrack:(NSUInteger)number confidenceLevel:(uint8_t)confidenceLevel CRC:(uint32_t)CRC;

- (id) initWithNumber:(NSUInteger)number confidenceLevel:(uint8_t)confidenceLevel CRC:(uint32_t)CRC;

@end
