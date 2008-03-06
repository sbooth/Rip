/*
 *  Copyright (C) 2008 Stephen F. Booth <me@sbooth.org>
 *  All Rights Reserved
 */

#import "EncoderManager.h"
#import "PlugInManager.h"
#import "EncoderInterface/EncoderInterface.h"

// ========================================
// KVC key names for the encoder dictionaries
// ========================================
NSString * const	kEncoderBundleKey						= @"bundle";
NSString * const	kEncoderSettingsKey						= @"settings";
NSString * const	kEncoderNicknameKey						= @"nickname";
NSString * const	kEncoderSelectedKey						= @"selected";

@implementation EncoderManager

@synthesize queue = _queue;

- (id) init
{
	if((self = [super init]))
		_queue = [[NSOperationQueue alloc] init];
	return self;
}

- (NSArray *) availableEncoders
{
	PlugInManager *plugInManager = [[[NSApplication sharedApplication] delegate] plugInManager];
	
	NSError *error = nil;
	NSArray *availableEncoders = [plugInManager plugInsConformingToProtocol:@protocol(EncoderInterface) error:&error];
	
	return availableEncoders;	
}

- (NSArray *) configuredEncoders
{
	return [[NSUserDefaults standardUserDefaults] arrayForKey:@"configuredEncoders"];
}

- (NSArray *) selectedEncoders
{
	NSPredicate *selectedEncodersPredicate = [NSPredicate predicateWithFormat:@"%K == 1", kEncoderSelectedKey];
	return [self.configuredEncoders filteredArrayUsingPredicate:selectedEncodersPredicate];
}

- (BOOL) encodeURL:(NSURL *)inputURL toURL:(NSURL *)outputURL metadata:(NSDictionary *)metadata
{
	NSParameterAssert(nil != inputURL);
	NSParameterAssert(nil != outputURL);

	return YES;
}

@end
