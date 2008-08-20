/*
 *  Copyright (C) 2008 Stephen F. Booth <me@sbooth.org>
 *  All Rights Reserved
 */

#import "PlugInManager.h"

// ========================================
// Constants
// ========================================
static NSString * const	kPlugInsFolderName						= @"PlugIns";

// ========================================
// Static variables
// ========================================
static PlugInManager *sSharedPlugInManager						= nil;

@implementation PlugInManager

+ (id) sharedPlugInManager
{
	if(!sSharedPlugInManager) {
		sSharedPlugInManager = [[PlugInManager alloc] init];
		
		NSError *error = nil;
		if(![sSharedPlugInManager scanForPlugIns:&error])
			[[NSApplication sharedApplication] presentError:error];
	}
	
	return sSharedPlugInManager;
}

- (id) init
{
	if((self = [super init]))
		_plugIns = [[NSMutableDictionary alloc] init];
	return self;
}

#pragma mark Properties

- (NSURL *) builtInPlugInsFolderURL
{
	return [NSURL fileURLWithPath:[[NSBundle mainBundle] builtInPlugInsPath]];
}

- (NSURL *) userPlugInsFolderURL
{
	NSArray *applicationSupportPaths = NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES);
	NSString *applicationSupportPath = (0 < applicationSupportPaths.count) ? [applicationSupportPaths objectAtIndex:0] : NSTemporaryDirectory();
	NSString *applicationName = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleName"];
	NSString *applicationSupportFolder = [applicationSupportPath stringByAppendingPathComponent:applicationName];
	NSString *userPlugInsFolder = [applicationSupportFolder stringByAppendingPathComponent:kPlugInsFolderName];
	
	return [NSURL fileURLWithPath:userPlugInsFolder];
}

- (NSURL *) localPlugInsFolderURL
{
	NSArray *applicationSupportPaths = NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSLocalDomainMask, YES);
	NSString *applicationSupportPath = (0 < applicationSupportPaths.count) ? [applicationSupportPaths objectAtIndex:0] : NSTemporaryDirectory();
	NSString *applicationName = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleName"];
	NSString *applicationSupportFolder = [applicationSupportPath stringByAppendingPathComponent:applicationName];
	NSString *localPlugInsFolder = [applicationSupportFolder stringByAppendingPathComponent:kPlugInsFolderName];
	
	return [NSURL fileURLWithPath:localPlugInsFolder];
}

#pragma mark Accessing PlugIns

- (NSArray *) allPlugIns
{
	return [_plugIns allValues];
}

- (NSArray *) allIdentifiers
{
	return [_plugIns allKeys];
}

- (NSArray *) plugInsConformingToProtocol:(Protocol *)protocol error:(NSError **)error
{
	NSParameterAssert(nil != protocol);
	
	NSMutableArray *conformingPlugIns = [[NSMutableArray alloc] init];
	
	for(NSBundle *plugIn in [_plugIns allValues]) {
		// Attempt to load the plug-in's executable code
		// Don't return nil; just store the error so that one bad plug-in won't prevent others from being detected
		if(![plugIn loadAndReturnError:error])
			continue;

		id plugInObject = [[[plugIn principalClass] alloc] init];
		if([plugInObject conformsToProtocol:protocol])
			[conformingPlugIns addObject:plugIn];

		// Clean up
		plugInObject = nil;
//		[plugIn unload];
	}
	
	return conformingPlugIns;
}

- (NSArray *) plugInsMatchingClass:(Class)class error:(NSError **)error
{
	NSParameterAssert(nil != class);

	NSMutableArray *matchingPlugIns = [[NSMutableArray alloc] init];
	
	for(NSBundle *plugIn in [_plugIns allValues]) {
		// Attempt to load the plug-in's executable code
		// Don't return nil; just store the error so that one bad plug-in won't prevent others from being detected
		if(![plugIn loadAndReturnError:error])
			continue;
		
		id plugInObject = [[[plugIn principalClass] alloc] init];
		if([plugInObject isKindOfClass:class])
			[matchingPlugIns addObject:plugIn];

		// Clean up
		plugInObject = nil;
//		[plugIn unload];
	}
	
	return matchingPlugIns;
	
}

- (NSBundle *) plugInForIdentifier:(NSString *)identifier
{
	NSParameterAssert(nil != identifier);
	
	return [_plugIns objectForKey:identifier];
}

- (BOOL) scanForPlugIns:(NSError **)error;
{
	BOOL result = YES;
	
	// Dump all previously found plug-ins
	[_plugIns removeAllObjects];
	
	// Scan these folders installed plug-ins
	NSArray *plugInsFolderURLS = [NSArray arrayWithObjects:
								  self.builtInPlugInsFolderURL,
								  self.userPlugInsFolderURL,
								  self.localPlugInsFolderURL, nil];
	
	// Iterate through each PlugIns folder
	for(NSURL *plugInsFolderURL in plugInsFolderURLS) {
		
		// Skip folders that don't exist
		NSString *plugInsFolderPath = [plugInsFolderURL path];
		if(![[NSFileManager defaultManager] fileExistsAtPath:plugInsFolderPath])
			continue;
		
		// Iterate through the directory contents and determine which files represent
		// plug-ins (as determined by NSBundle)
		NSArray *plugInDirectoryContents = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:plugInsFolderPath error:error];
		if(plugInDirectoryContents) {
			for(NSString *plugInName in plugInDirectoryContents) {
				NSString *plugInPath = [plugInsFolderPath stringByAppendingPathComponent:plugInName];
				NSBundle *plugInBundle = [NSBundle bundleWithPath:plugInPath];

				// Register the plug-in
				if(plugInBundle && ![plugInBundle isEqual:[NSBundle mainBundle]])
					[_plugIns setObject:plugInBundle forKey:[plugInBundle bundleIdentifier]];
			}
		}
		else
			result = NO;
	}
	
	return result;
}

@end
