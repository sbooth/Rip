/*
 *  $Id$
 *  Copyright (C) 2007 Stephen F. Booth <me@sbooth.org>
 *  All Rights Reserved
 */

#import <Cocoa/Cocoa.h>

// ========================================
// Interprets an NSInteger as an CD sector count and formats it as bytes, KB, MB, GB, TB, or PB
// ========================================
@interface ByteSizeFormatter : NSFormatter
{
	NSNumberFormatter *_numberFormatter;
}

@end
