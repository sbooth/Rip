/*
 *  Copyright (C) 2008 Stephen F. Booth <me@sbooth.org>
 *  All Rights Reserved
 */

#import "ByteSizeValueTransformer.h"
#import "ByteSizeFormatter.h"

@implementation ByteSizeValueTransformer

- (id) init
{
	if((self = [super init]))
		_formatter = [[ByteSizeFormatter alloc] init];
	return self;
}

+ (Class) transformedValueClass
{
	return [NSString class];
}

+ (BOOL) allowsReverseTransformation
{
	return NO;
}

- (id) transformedValue:(id)value
{
	return [_formatter stringForObjectValue:value];
}

@end
