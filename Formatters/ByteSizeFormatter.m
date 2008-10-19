/*
 *  Copyright (C) 2007 Stephen F. Booth <me@sbooth.org>
 *  All Rights Reserved
 */

#import "ByteSizeFormatter.h"

#include <IOKit/storage/IOCDTypes.h>

@implementation ByteSizeFormatter

- (id) init
{
	if((self = [super init])) {
		_numberFormatter = [[NSNumberFormatter alloc] init];
		[_numberFormatter setFormatterBehavior:NSNumberFormatterBehavior10_4];
		[_numberFormatter setNumberStyle:NSNumberFormatterDecimalStyle];
	}
	return self;
}

- (NSString *) stringForObjectValue:(id)anObject
{
	if(!anObject || ![anObject respondsToSelector:@selector(integerValue)])
		return nil;
	
	NSUInteger sectorCount = [anObject integerValue];
	NSUInteger byteSize = kCDSectorSizeCDDA * sectorCount;
	float size = byteSize;
	NSUInteger divisions = 1;
	
	while(1024 < size) {
		size /= 1024;
		++divisions;
	}
	
	switch(divisions) {
		case 1:		[_numberFormatter setPositiveSuffix:NSLocalizedString(@" bytes", @"")];				break;
		case 2:		[_numberFormatter setPositiveSuffix:NSLocalizedString(@" KB", @"kilobytes")];		break;
		case 3:		[_numberFormatter setPositiveSuffix:NSLocalizedString(@" MB", @"megabytes")];		break;
		case 4:		[_numberFormatter setPositiveSuffix:NSLocalizedString(@" GB", @"gigabytes")];		break;
		case 5:		[_numberFormatter setPositiveSuffix:NSLocalizedString(@" TB", @"terabytes")];		break;
		case 6:		[_numberFormatter setPositiveSuffix:NSLocalizedString(@" PB", @"petabytes")];		break;
		case 7:		[_numberFormatter setPositiveSuffix:NSLocalizedString(@" EB", @"exabytes")];		break;
		case 8:		[_numberFormatter setPositiveSuffix:NSLocalizedString(@" ZB", @"zettabytes")];		break;
		case 9:		[_numberFormatter setPositiveSuffix:NSLocalizedString(@" YB", @"yottabytes")];		break;
	}
	
	return [_numberFormatter stringForObjectValue:[NSNumber numberWithFloat:size]];
}

- (NSAttributedString *) attributedStringForObjectValue:(id)object withDefaultAttributes:(NSDictionary *)attributes
{
	return [[NSAttributedString alloc] initWithString:[self stringForObjectValue:object] attributes:attributes];
}

@end
