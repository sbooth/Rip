/*
 *  Copyright (C) 2007 - 2008 Stephen F. Booth <me@sbooth.org>
 *  All Rights Reserved
 */

#import <Cocoa/Cocoa.h>
#import "EncoderInterface/EncodingOperation.h"

// ========================================
// KVC key names for the properties dictionary
// ========================================
extern NSString * const		kFLACCompressionLevelKey;	// NSNumber * (int)

// ========================================
// An EncodingOperation subclass that transcodes CDDA audio to FLAC
// ========================================
@interface FLACEncodeOperation : EncodingOperation
{
}

@end
