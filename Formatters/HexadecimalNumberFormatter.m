/*
 *  Copyright (C) 2008 Stephen F. Booth <me@sbooth.org>
 *  All Rights Reserved
 */

#import "HexadecimalNumberFormatter.h"

@implementation HexadecimalNumberFormatter

@synthesize width = _width;

- (NSString *) stringForObjectValue:(id)anObject
{
	if(!anObject || ![anObject respondsToSelector:@selector(integerValue)])
		return nil;
	
	NSString *formatString = @"%lx";
	if(self.width)
		formatString = [NSString stringWithFormat:@"%%0%llx", self.width];

	return [NSString stringWithFormat:formatString, [anObject integerValue]];
}

- (BOOL) getObjectValue:(id *)object forString:(NSString *)string errorDescription:(NSString  **)error
{
	NSScanner *scanner = [[NSScanner alloc] initWithString:string];
	unsigned value = 0;
	BOOL result = [scanner scanHexInt:&value];
	
	if(result && NULL != object)
		*object = [NSNumber numberWithUnsignedInt:value];
	else if(NULL != error)
		*error = [NSString stringWithFormat:@"Couldn't convert \"%@\" to unsigned int", string];
	
	return result;
}

- (NSAttributedString *) attributedStringForObjectValue:(id)object withDefaultAttributes:(NSDictionary *)attributes
{
	return [[NSAttributedString alloc] initWithString:[self stringForObjectValue:object] attributes:attributes];
}

@end
