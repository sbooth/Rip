/*
 *  Copyright (C) 2008 Stephen F. Booth <me@sbooth.org>
 *  All Rights Reserved
 */

#import <Cocoa/Cocoa.h>

// ========================================
// Value transformer interface to ByteSizeFormatter, for bindings
// ========================================
@interface ByteSizeValueTransformer : NSValueTransformer
{
	NSFormatter *_formatter;
}

@end
