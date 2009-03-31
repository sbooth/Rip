/*
 *  Copyright (C) 2008 - 2009 Stephen F. Booth <me@sbooth.org>
 *  All Rights Reserved
 */

#import <Cocoa/Cocoa.h>

// ========================================
// Class that manages an application's plug-ins (bundles in PlugIns folder)
// ========================================
@interface PlugInManager : NSObject
{
@private
	NSMutableDictionary *_plugIns;
}

// ========================================
// Folder locations
@property (readonly) NSURL * builtInPlugInsFolderURL;
@property (readonly) NSURL * userPlugInsFolderURL;
@property (readonly) NSURL * localPlugInsFolderURL;

// ========================================
// The shared instance
+ (id) sharedPlugInManager;

// ========================================
// Accessing PlugIns
- (NSArray *) allPlugIns;
- (NSArray *) allIdentifiers;

- (NSArray *) plugInsConformingToProtocol:(Protocol *)protocol error:(NSError **)error;
- (NSArray *) plugInsMatchingClass:(Class)class error:(NSError **)error;

- (NSBundle *) plugInForIdentifier:(NSString *)identifier;

// ========================================
// Scan all PlugIn folders for available PlugIns
- (BOOL) scanForPlugIns:(NSError **)error;

@end
