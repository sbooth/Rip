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

@class ExtractionRecord;

@interface EncoderManager : NSObject
{
	@private
	NSOperationQueue *_queue;
}

// Returns an array of NSDictionary * for all encoders the user has configured
//@property (readonly) NSArray * configuredEncoders;

// Returns an array of NSDictionary * for all encoders the user has configured and selected
//@property (readonly) NSArray * selectedEncoders;

//@property (readonly) NSOperationQueue * queue; 

// ========================================
// Returns an array of NSBundle * objects whose principalClasses implement the EncoderInterface protocol
@property (readonly) NSArray * availableEncoders;

// ========================================
// Returns an NSBundle * object corresponding to the user's default encoder
@property (assign) NSBundle * defaultEncoder;

// ========================================
// The shared instance
+ (id) sharedEncoderManager;

// ========================================
// Access to stored encoder settings
- (NSDictionary *) settingsForEncoder:(NSBundle *)encoder;
- (void) storeSettings:(NSDictionary *)encoderSettings forEncoder:(NSBundle *)encoder;

// Queue an encoding request
- (BOOL) encodeURL:(NSURL *)inputURL extractionRecord:(ExtractionRecord *)extractionRecord error:(NSError **)error;

@end
