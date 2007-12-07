/*
 *  $Id$
 *  Copyright (C) 2007 Stephen F. Booth <me@sbooth.org>
 *  All Rights Reserved
 */

#import "YesNoFormatter.h"

@implementation YesNoFormatter

- (NSString *) stringForObjectValue:(id)anObject
{
	if(nil == anObject || ! [anObject respondsToSelector:@selector(integerValue)])
		return nil;
	
	if([anObject integerValue])
		return NSLocalizedStringFromTable(@"Yes", @"General", @"");
	else
		return NSLocalizedStringFromTable(@"No", @"General", @"");
}

- (BOOL) getObjectValue:(id *)object forString:(NSString *)string errorDescription:(NSString  **)error
{
	BOOL result = NO;
	BOOL value = NO;

	if([string hasPrefix:NSLocalizedStringFromTable(@"Yes", @"General", @"")]) {
		value = YES;
		result = YES;
	}
	else if([string hasPrefix:NSLocalizedStringFromTable(@"No", @"General", @"")]) {
		value = NO;
		result = YES;
	}
	   
	if(result && NULL != object)
		*object = [NSNumber numberWithBool:value];
	else if(NULL != error)
		*error = @"Couldn't convert Yes/No to BOOL";

	return result;
}

- (NSAttributedString *) attributedStringForObjectValue:(id)object withDefaultAttributes:(NSDictionary *)attributes
{
	return [[NSAttributedString alloc] initWithString:[self stringForObjectValue:object] attributes:attributes];
}

@end
