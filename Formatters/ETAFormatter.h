/*
 *  Copyright (C) 2009 Stephen F. Booth <me@sbooth.org>
 *  All Rights Reserved
 */

#import <Cocoa/Cocoa.h>

@interface ETAFormatter : NSFormatter
{
@private
	BOOL _includeSeconds;
}

@property (assign) BOOL includeSeconds;

@end
