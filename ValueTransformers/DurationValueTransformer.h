/*
 *  Copyright (C) 2008 Stephen F. Booth <me@sbooth.org>
 *  All Rights Reserved
 */

#import <Cocoa/Cocoa.h>

// ========================================
// Value transformer interface to DurationFormatter, for bindings
// ========================================
@interface DurationValueTransformer : NSValueTransformer
{
	NSFormatter *_formatter;
}

@end
