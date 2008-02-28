/*
 *  Copyright (C) 2008 Stephen F. Booth <me@sbooth.org>
 *  All Rights Reserved
 */

#import "PlugInManager.h"

// Constants
static NSString * const	kPlugInsFolderName						= @"PlugIns";

@interface PlugInManager (Private)
- (void) scanForPlugins;
@end

@implementation PlugInManager

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

- (id) init
{
	if((self = [super init])) {
		_plugIns = [[NSMutableDictionary alloc] init];
		[self scanForPlugins];
	}
	return self;
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

- (NSArray *) plugInsConformingToProtocol:(Protocol *)protocol
{
	NSParameterAssert(nil != protocol);
	
	NSMutableArray *conformingPlugIns = [[NSMutableArray alloc] init];
	
	for(NSBundle *plugIn in _plugIns) {
		id plugInObject = [[[plugIn principalClass] alloc] init];
		if([plugInObject conformsToProtocol:protocol])
			[conformingPlugIns addObject:plugIn];
		plugInObject = nil;
	}
	
	return conformingPlugIns;
}

- (NSArray *) plugInsMatchingClass:(Class)class
{
	NSParameterAssert(nil != class);

	NSMutableArray *matchingPlugIns = [[NSMutableArray alloc] init];
	
	for(NSBundle *plugIn in _plugIns) {
		id plugInObject = [[[plugIn principalClass] alloc] init];
		if([plugInObject isKindOfClass:class])
			[matchingPlugIns addObject:plugIn];
		plugInObject = nil;
	}
	
	return matchingPlugIns;
	
}

- (NSBundle *) plugInForIdentifier:(NSString *)identifier
{
	NSParameterAssert(nil != identifier);
	
	return [_plugIns objectForKey:identifier];
}

@end

@implementation PlugInManager (Private)

- (void) scanForPlugins
{
	// Scan for installed plug-ins
	NSArray *plugInsFolderURLS = [NSArray arrayWithObjects:
								  self.builtInPlugInsFolderURL,
								  self.userPlugInsFolderURL,
								  self.localPlugInsFolderURL, nil];
	NSError *error = nil;
	
	// Iterate through each PlugIns folder
	for(NSURL *plugInsFolderURL in plugInsFolderURLS) {
		
		NSString *plugInsFolderPath = [plugInsFolderURL path];
		if(![[NSFileManager defaultManager] fileExistsAtPath:plugInsFolderPath])
			continue;
		
		NSArray *plugInDirectoryContents = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:plugInsFolderPath error:&error];
		if(plugInDirectoryContents) {
			for(NSString *plugInName in plugInDirectoryContents) {
				NSString *plugInPath = [plugInsFolderPath stringByAppendingPathComponent:plugInName];
				NSBundle *plugInBundle = [NSBundle bundleWithPath:plugInPath];

				// Register the plug-in
				if(plugInBundle)
					[_plugIns setObject:plugInBundle forKey:[plugInBundle bundleIdentifier]];
					
//				[plugInBundle unload];
			}
		}
		else
			[[NSApplication sharedApplication] presentError:error];
	}
	
	NSLog(@"PlugIn scan complete: %@",_plugIns);
}

@end
