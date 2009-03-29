/*
 *  Copyright (C) 2009 Stephen F. Booth <me@sbooth.org>
 *  All Rights Reserved
 */

#import "SecondsFormatter.h"

@implementation SecondsFormatter

- (NSString *) stringForObjectValue:(id)anObject
{
	if(!anObject || ![anObject respondsToSelector:@selector(integerValue)])
		return nil;
	
	NSUInteger value = [anObject integerValue];

	NSUInteger hours = 0;
	NSUInteger seconds = value % 60;
	NSUInteger minutes = value / 60;
	
	while(60 <= minutes) {
		minutes -= 60;
		++hours;
	}
	
	NSString *result = nil;
	if(0 < hours)
		result = [NSString stringWithFormat:@"%u:%u:%.2u", hours, minutes, seconds];
//	else if(0 < minutes)
	else
		result = [NSString stringWithFormat:@"%u:%.2u", minutes, seconds];
//	else
//		result = [NSString stringWithFormat:NSLocalizedString(@"%u seconds", @""), seconds];
	
	return result;
}

- (BOOL) getObjectValue:(id *)object forString:(NSString *)string errorDescription:(NSString  **)error
{
	BOOL result = NO;
	NSUInteger seconds = 0;
	
	NSScanner *scanner = [NSScanner scannerWithString:string];
	while(![scanner isAtEnd]) {
		// Grab a value
		NSUInteger value = 0;
		if([scanner scanInteger:(NSInteger *)&value]) {
			seconds *= 60;
			seconds += value;
			result = YES;
		}
		
		// Grab the separator, if present
		[scanner scanString:@":" intoString:NULL];
	}
	
	if(result && NULL != object)
		*object = [NSNumber numberWithUnsignedInteger:seconds];
	else if(NULL != error)
		*error = @"Couldn't convert to seconds";
	
	return result;
}

- (NSAttributedString *) attributedStringForObjectValue:(id)object withDefaultAttributes:(NSDictionary *)attributes
{
	return [[NSAttributedString alloc] initWithString:[self stringForObjectValue:object] attributes:attributes];
}

@end
