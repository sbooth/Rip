/*
 *  Copyright (C) 2009 Stephen F. Booth <me@sbooth.org>
 *  All Rights Reserved
 */

#import "ChannelFormatter.h"

@implementation ChannelFormatter

- (NSString *) stringForObjectValue:(id)anObject
{
	if(!anObject || ![anObject respondsToSelector:@selector(integerValue)])
		return nil;
	
	switch([anObject integerValue]) {
		case 1:
			return NSLocalizedString(@"Mono", @"");
		case 2:
			return NSLocalizedString(@"Stereo", @"");
		case 4:
			return NSLocalizedString(@"Quadraphonic", @"");
	}

	return [anObject stringValue];
}

- (BOOL) getObjectValue:(id *)object forString:(NSString *)string errorDescription:(NSString  **)error
{
	BOOL result = NO;
	NSInteger value = 0;
	
	if([string hasPrefix:NSLocalizedString(@"Mono", @"")]) {
		value = 1;
		result = YES;
	}
	else if([string hasPrefix:NSLocalizedString(@"Stereo", @"")]) {
		value = 2;
		result = YES;
	}
	else if([string hasPrefix:NSLocalizedString(@"Quadraphonic", @"")]) {
		value = 4;
		result = YES;
	}
	
	if(result && NULL != object)
		*object = [NSNumber numberWithBool:value];
	else if(NULL != error)
		*error = @"Couldn't convert channel description to integer";
	
	return result;
}

- (NSAttributedString *) attributedStringForObjectValue:(id)object withDefaultAttributes:(NSDictionary *)attributes
{
	return [[NSAttributedString alloc] initWithString:[self stringForObjectValue:object] attributes:attributes];
}

@end
