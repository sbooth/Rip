/*
 *  Copyright (C) 2009 Stephen F. Booth <me@sbooth.org>
 *  All Rights Reserved
 */

#import <Cocoa/Cocoa.h>

// ========================================
// KVC key names for the encoder dictionaries
// ========================================
extern NSString * const		kMetadataSourceBundleKey; // NSBundle *
extern NSString * const		kMetadataSourceSettingsKey; // NSDictionary *

@interface MetadataSourceManager : NSObject
{
}

// ========================================
// Returns an array of NSBundle * objects whose principalClasses implement the MetadataSourceInterface protocol
@property (readonly) NSArray * availableMetadataSources;

// ========================================
// The shared instance
+ (id) sharedMetadataSourceManager;

// ========================================
// Access to stored metadata source settings
- (NSDictionary *) settingsForMetadataSource:(NSBundle *)metadataSource;
- (void) storeSettings:(NSDictionary *)metadataSourceSettings forMetadataSource:(NSBundle *)metadataSource;
- (void) restoreDefaultSettingsForMetadataSource:(NSBundle *)metadataSource;

@end
