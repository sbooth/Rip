/*
 *  Copyright (C) 2008 Stephen F. Booth <me@sbooth.org>
 *  All Rights Reserved
 */

#import <Cocoa/Cocoa.h>

@class EncodingOperation;

// ========================================
// The interface encoders must implement to integrate with Rip
// ========================================
@interface EncoderInterface : NSObject
{
}

// Encoder information, for presentation in a list of available encoders
@property (readonly) NSString * encoderName;
@property (readonly) NSImage * encoderIcon;

// Create an instance of NSViewController allowing users to edit the encoder's configuration
// The controller's representedObject will be set to the applicable encoder settings (NSDictionary *)
- (NSViewController *) configurationViewController;

// Provide an instance of an EncodingOperation subclass
- (EncodingOperation *) encodingOperation;

@end
