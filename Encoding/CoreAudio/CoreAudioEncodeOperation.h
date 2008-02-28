/*
 *  Copyright (C) 2007 - 2008 Stephen F. Booth <me@sbooth.org>
 *  All Rights Reserved
 */

#import <Cocoa/Cocoa.h>
#import "EncoderInterface/EncodingOperation.h"

#include <AudioToolbox/AudioFile.h>

// ========================================
// KVC key names for the properties dictionary
// ========================================
extern NSString * const		kAudioConverterConfigKey;	// id (CFPropertyListRef)
extern NSString * const		kAudioFileTypeKey;			// NSNumber * (int)
extern NSString * const		kStreamDescriptionKey;		// NSData * (AudioStreamBasicDescription)

// ========================================
// An EncodingOperation subclass that transcodes CDDA audio using Apple's Core Audio
// ========================================
@interface CoreAudioEncodeOperation : EncodingOperation
{
}

@property (readonly) AudioFileTypeID fileType;
@property (readonly) AudioStreamBasicDescription streamDescription;

@end
