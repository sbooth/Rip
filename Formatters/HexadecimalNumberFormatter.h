/*
 *  Copyright (C) 2008 Stephen F. Booth <me@sbooth.org>
 *  All Rights Reserved
 */

#import <Cocoa/Cocoa.h>

// ========================================
// Formats an unsigned int as hex
// ========================================
@interface HexadecimalNumberFormatter : NSFormatter
{
	NSUInteger _width;
}

@property (assign) NSUInteger width;

@end
