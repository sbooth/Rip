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
		case 2:		[_numberFormatter setPositiveSuffix:NSLocalizedString(@" KiB", @"kibibytes")];		break;
		case 3:		[_numberFormatter setPositiveSuffix:NSLocalizedString(@" MiB", @"mebibytes")];		break;
		case 4:		[_numberFormatter setPositiveSuffix:NSLocalizedString(@" GiB", @"gibibytes")];		break;
		case 5:		[_numberFormatter setPositiveSuffix:NSLocalizedString(@" TiB", @"tebibytes")];		break;
		case 6:		[_numberFormatter setPositiveSuffix:NSLocalizedString(@" PiB", @"pebibytes")];		break;
		case 7:		[_numberFormatter setPositiveSuffix:NSLocalizedString(@" EiB", @"exbibytes")];		break;
		case 8:		[_numberFormatter setPositiveSuffix:NSLocalizedString(@" ZiB", @"zebibytes")];		break;
		case 9:		[_numberFormatter setPositiveSuffix:NSLocalizedString(@" YiB", @"yobibytes")];		break;
	}
	
	return [_numberFormatter stringForObjectValue:[NSNumber numberWithFloat:size]];
}

- (NSAttributedString *) attributedStringForObjectValue:(id)object withDefaultAttributes:(NSDictionary *)attributes
{
	return [[NSAttributedString alloc] initWithString:[self stringForObjectValue:object] attributes:attributes];
}

@end
