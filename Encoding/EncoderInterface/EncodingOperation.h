/*
 *  Copyright (C) 2008 Stephen F. Booth <me@sbooth.org>
 *  All Rights Reserved
 */

#import <Cocoa/Cocoa.h>

// ========================================
// An NSOperation subclass that defines the interface to be implemented by encoder plug-ins
// ========================================
@interface EncodingOperation : NSOperation
{
	NSURL *_inputURL;
	NSURL *_outputURL;
	NSDictionary *_settings;
	NSDictionary *_metadata;
	NSError *_error;
}

@property (assign) NSURL * inputURL;
@property (assign) NSURL * outputURL;
@property (copy) NSDictionary * settings;
@property (copy) NSDictionary * metadata;
@property (assign) NSError * error;

// Optional properties
@property (readonly) NSNumber * progress;

@end
