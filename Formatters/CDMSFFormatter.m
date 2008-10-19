/*
 *  Copyright (C) 2007 - 2008 Stephen F. Booth <me@sbooth.org>
 *  All Rights Reserved
 */

#import "CDMSFFormatter.h"

#include <IOKit/storage/IOCDTypes.h>

@implementation CDMSFFormatter

- (NSString *) stringForObjectValue:(id)anObject
{
	if(!anObject || ![anObject respondsToSelector:@selector(integerValue)])
		return nil;
	
	NSUInteger offset = [anObject integerValue];
	CDMSF msf = CDConvertLBAToMSF(offset);

	return [NSString stringWithFormat:@"%02i:%02i.%02i", msf.minute, msf.second, msf.frame];
}

- (BOOL) getObjectValue:(id *)object forString:(NSString *)string errorDescription:(NSString  **)error
{
	CDMSF		msf			= { 0xFF, 0xFF, 0xFF };
	BOOL		result		= NO;
	NSInteger	value;

	NSScanner *scanner = [NSScanner scannerWithString:string];

	if([scanner scanInteger:&value]) {
		msf.minute = value;
		result = YES;
	}

	[scanner scanString:@":" intoString:NULL];

	if([scanner scanInteger:&value]) {
		msf.second = value;
		result = YES;
	}

	[scanner scanString:@"." intoString:NULL];

	if([scanner scanInteger:&value]) {
		msf.frame = value;
		result = YES;
	}
	
	if(result && NULL != object)
		*object = [NSNumber numberWithUnsignedInt:CDConvertMSFToLBA(msf)];
	else if(NULL != error)
		*error = @"Couldn't convert MM:SS.FF to CDMSF";

	return result;
}

- (NSAttributedString *) attributedStringForObjectValue:(id)object withDefaultAttributes:(NSDictionary *)attributes
{
	return [[NSAttributedString alloc] initWithString:[self stringForObjectValue:object] attributes:attributes];
}
							 
@end
