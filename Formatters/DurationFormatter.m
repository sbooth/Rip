/*
 *  Copyright (C) 2007 - 2008 Stephen F. Booth <me@sbooth.org>
 *  All Rights Reserved
 */

#import "DurationFormatter.h"

#include <IOKit/storage/IOCDTypes.h>

@implementation DurationFormatter

- (NSString *) stringForObjectValue:(id)anObject
{
	if(!anObject || ![anObject respondsToSelector:@selector(integerValue)])
		return nil;
	
	NSUInteger offset = [anObject integerValue];
	CDMSF msf = CDConvertLBAToMSF(offset - 150);
	
	// Round to nearest second
	if(37 < msf.frame) {
		msf.second += 1;
		if(60 < msf.second) {
			msf.minute += 1;
			msf.second -= 60;
		}
	}
	
	return [NSString stringWithFormat:@"%i:%02i", msf.minute, msf.second];
}

- (BOOL) getObjectValue:(id *)object forString:(NSString *)string errorDescription:(NSString  **)error
{
	CDMSF		msf			= { 0xFF, 0xFF, 0x00 };
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
	
	if(result && NULL != object)
		*object = [NSNumber numberWithUnsignedInt:(CDConvertMSFToLBA(msf) + 150)];
	else if(NULL != error)
		*error = @"Couldn't convert MM:SS to a sector count";
	
	return result;
}

- (NSAttributedString *) attributedStringForObjectValue:(id)object withDefaultAttributes:(NSDictionary *)attributes
{
	return [[NSAttributedString alloc] initWithString:[self stringForObjectValue:object] attributes:attributes];
}

@end
