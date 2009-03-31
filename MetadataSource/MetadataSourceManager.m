/*
 *  Copyright (C) 2009 Stephen F. Booth <me@sbooth.org>
 *  All Rights Reserved
 */

#import "MetadataSourceManager.h"
#import "PlugInManager.h"
#import "MetadataSourceInterface/MetadataSourceInterface.h"

// ========================================
// Sorting function for sorting bundles by metadata source names
// ========================================
static NSComparisonResult
metadataSourceBundleSortFunction(id bundleA, id bundleB, void *context)
{

#pragma unused(context)
	
	NSCParameterAssert(nil != bundleA);
	NSCParameterAssert(nil != bundleB);
	NSCParameterAssert([bundleA isKindOfClass:[NSBundle class]]);
	NSCParameterAssert([bundleB isKindOfClass:[NSBundle class]]);
	
	NSString *bundleAName = [bundleA objectForInfoDictionaryKey:@"MetadataSourceName"];
	NSString *bundleBName = [bundleB objectForInfoDictionaryKey:@"MetadataSourceName"];
	
	return [bundleAName compare:bundleBName];;
}

// ========================================
// KVC key names for the metadata source dictionaries
// ========================================
NSString * const	kMetadataSourceBundleKey				= @"bundle";
NSString * const	kMetadataSourceSettingsKey				= @"settings";

// ========================================
// Static variables
// ========================================
static MetadataSourceManager *sSharedMetadataSourceManager	= nil;

@implementation MetadataSourceManager

+ (id) sharedMetadataSourceManager
{
	if(!sSharedMetadataSourceManager)
		sSharedMetadataSourceManager = [[self alloc] init];
	return sSharedMetadataSourceManager;
}

- (NSArray *) availableMetadataSources
{
	PlugInManager *plugInManager = [PlugInManager sharedPlugInManager];
	
	NSError *error = nil;
	NSArray *availableMetadataSources = [plugInManager plugInsConformingToProtocol:@protocol(MetadataSourceInterface) error:&error];
	
	return [availableMetadataSources sortedArrayUsingFunction:metadataSourceBundleSortFunction context:NULL];
}

- (NSDictionary *) settingsForMetadataSource:(NSBundle *)metadataSource
{
	NSParameterAssert(nil != metadataSource);
	
	// Verify this is a valid metadata source
	if(![self.availableMetadataSources containsObject:metadataSource])
		return nil;
	
	NSString *bundleIdentifier = [metadataSource bundleIdentifier];
	NSDictionary *metadataSourceSettings = [[NSUserDefaults standardUserDefaults] dictionaryForKey:bundleIdentifier];
	
	// If no settings are present for this metadata source, use the defaults
	if(!metadataSourceSettings) {
		// Instantiate the metadata source interface
		id <MetadataSourceInterface> metadataSourceInterface = [[[metadataSource principalClass] alloc] init];
		
		// Grab the metadata source's settings dictionary
		metadataSourceSettings = [metadataSourceInterface defaultSettings];
		
		// Store the defaults
		if(metadataSourceSettings)
			[[NSUserDefaults standardUserDefaults] setObject:metadataSourceSettings forKey:bundleIdentifier];
	}
	
	return [metadataSourceSettings copy];
}

- (void) storeSettings:(NSDictionary *)metadataSourceSettings forMetadataSource:(NSBundle *)metadataSource
{
	NSParameterAssert(nil != metadataSource);
	
	// Verify this is a valid metadata source
	if(![self.availableMetadataSources containsObject:metadataSource])
		return;
	
	NSString *bundleIdentifier = [metadataSource bundleIdentifier];
	if(metadataSourceSettings)
		[[NSUserDefaults standardUserDefaults] setObject:metadataSourceSettings forKey:bundleIdentifier];
	else
		[[NSUserDefaults standardUserDefaults] removeObjectForKey:bundleIdentifier];
}

- (void) restoreDefaultSettingsForMetadataSource:(NSBundle *)metadataSource
{
	NSParameterAssert(nil != metadataSource);
	
	// Verify this is a valid metadata source
	if(![self.availableMetadataSources containsObject:metadataSource])
		return;
	
	NSString *bundleIdentifier = [metadataSource bundleIdentifier];
	
	// Instantiate the metadata source interface
	id <MetadataSourceInterface> metadataSourceInterface = [[[metadataSource principalClass] alloc] init];
	
	// Grab the metadata source's settings dictionary
	NSDictionary *metadataSourceSettings = [metadataSourceInterface defaultSettings];
	
	// Store the defaults
	if(metadataSourceSettings)
		[[NSUserDefaults standardUserDefaults] setObject:metadataSourceSettings forKey:bundleIdentifier];
	else
		[[NSUserDefaults standardUserDefaults] removeObjectForKey:bundleIdentifier];
}

@end
