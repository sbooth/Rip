/*
 *  Copyright (C) 2008 Stephen F. Booth <me@sbooth.org>
 *  All Rights Reserved
 */

#import <Cocoa/Cocoa.h>

@interface PlugInManager : NSObject
{
	@private
	NSMutableDictionary *_plugIns;
}

// Folder locations
@property (readonly) NSURL * builtInPlugInsFolderURL;
@property (readonly) NSURL * userPlugInsFolderURL;
@property (readonly) NSURL * localPlugInsFolderURL;

// Accessing PlugIns
- (NSArray *) allPlugIns;
- (NSArray *) allIdentifiers;

- (NSArray *) plugInsConformingToProtocol:(Protocol *)protocol;
- (NSArray *) plugInsMatchingClass:(Class)class;

- (NSBundle *) plugInForIdentifier:(NSString *)identifier;

@end
