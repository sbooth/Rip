/*
 *  Copyright (C) 2008 Stephen F. Booth <me@sbooth.org>
 *  All Rights Reserved
 */

#import "DurationValueTransformer.h"
#import "DurationFormatter.h"

@implementation DurationValueTransformer

- (id) init
{
	if((self = [super init]))
		_formatter = [[DurationFormatter alloc] init];
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
