/*
 *  Copyright (C) 2009 Stephen F. Booth <me@sbooth.org>
 *  All Rights Reserved
 */

#import <Cocoa/Cocoa.h>
#import "EncoderInterface/EncodingOperation.h"

// ========================================
// KVC key names for the properties dictionary
// ========================================
extern NSString * const		kWavPackCompressionModeKey;		// NSNumber * (int)
extern NSString * const		kWavPackComputeMD5Key;			// NSNumber * (BOOL)

// ========================================
// Enum for user defaults output file handling
// ========================================
enum _eWavPackCompressionMode {
	eWavPackCompressionModeFast = -1,
	eWavPackCompressionModeNormal = 0,
	eWavPackCompressionModeHigh = 1,
	eWavPackCompressionModeVeryHigh = 2
};
typedef enum _eWavPackCompressionMode eWavPackCompressionMode;

// ========================================
// An EncodingOperation subclass that transcodes CDDA audio to WavPack
// ========================================
@interface WavPackEncodeOperation : EncodingOperation
{
}

@end
