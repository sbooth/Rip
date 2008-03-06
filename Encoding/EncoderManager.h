/*
 *  Copyright (C) 2008 Stephen F. Booth <me@sbooth.org>
 *  All Rights Reserved
 */

#import <Cocoa/Cocoa.h>

// ========================================
// KVC key names for the encoder dictionaries
// ========================================
extern NSString * const		kEncoderBundleKey; // NSBundle *
extern NSString * const		kEncoderSettingsKey; // NSDictionary *
extern NSString * const		kEncoderNicknameKey; // NSString *
extern NSString * const		kEncoderSelectedKey; // NSNumber *

@interface EncoderManager : NSObject
{
	@private
	NSOperationQueue *_queue;
}

// Returns an array of NSBundle * objects whose principalClasse implement the EncoderInterface protocol
@property (readonly) NSArray * availableEncoders;

// Returns an array of NSDictionary * for all encoders the user has configured
@property (readonly) NSArray * configuredEncoders;

// Returns an array of NSDictionary * for all encoders the user has configured and selected
@property (readonly) NSArray * selectedEncoders;

@property (readonly) NSOperationQueue * queue; 

// Queue an encoding request
- (BOOL) encodeURL:(NSURL *)inputURL toURL:(NSURL *)outputURL metadata:(NSDictionary *)metadata;

@end
