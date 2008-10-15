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

@class CompactDisc, ExtractionRecord;

@interface EncoderManager : NSObject
{
@private
	NSOperationQueue *_queue;
}

// The operation queue used for encoding
@property (readonly) NSOperationQueue * queue; 

// ========================================
// Returns an array of NSBundle * objects whose principalClasses implement the EncoderInterface protocol
@property (readonly) NSArray * availableEncoders;

// ========================================
// Returns an NSBundle * object corresponding to the user's default encoder
@property (assign) NSBundle * defaultEncoder;
@property (assign) NSDictionary * defaultEncoderSettings;

// ========================================
// The shared instance
+ (id) sharedEncoderManager;

// ========================================
// Access to stored encoder settings
- (NSDictionary *) settingsForEncoder:(NSBundle *)encoder;
- (void) storeSettings:(NSDictionary *)encoderSettings forEncoder:(NSBundle *)encoder;
- (void) restoreDefaultSettingsForEncoder:(NSBundle *)encoder;

// ========================================
// Get the URL for the output folder to use for the given disc
- (NSURL *) outputURLForCompactDisc:(CompactDisc *)disc;

// ========================================
// Queue an encoding request
- (BOOL) encodeURL:(NSURL *)inputURL extractionRecord:(ExtractionRecord *)extractionRecord error:(NSError **)error;

@end
