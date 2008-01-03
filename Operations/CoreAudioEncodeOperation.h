/*
 *  Copyright (C) 2007 Stephen F. Booth <me@sbooth.org>
 *  All Rights Reserved
 */

#import <Cocoa/Cocoa.h>
#include <AudioToolbox/AudioFile.h>

// ========================================
// An NSOperation subclass that transcodes audio from one format to another
// ========================================
@interface CoreAudioEncodeOperation : NSOperation
{
	NSURL *_inputURL;
	NSURL *_outputURL;
	AudioFileTypeID _fileType;
	AudioStreamBasicDescription _streamDescription;
	NSArray *_propertySettings;
	NSError *_error;
}

@property (copy) NSURL * inputURL;
@property (copy) NSURL * outputURL;
@property (assign) AudioFileTypeID fileType;
@property (assign) AudioStreamBasicDescription streamDescription;
@property (copy) NSArray * propertySettings;
@property (readonly, copy) NSError * error;

@end
