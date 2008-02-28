/*
 *  Copyright (C) 2008 Stephen F. Booth <me@sbooth.org>
 *  All Rights Reserved
 */

#import "EncoderInterface.h"

@implementation EncoderInterface

- (NSString*) encoderName
{
	return @"ENCODER NAME";
}

- (NSImage *) encoderIcon
{
	return nil;
}

- (NSViewController *) configurationViewController
{
	return nil;
}

- (EncodingOperation *) encodingOperation
{
	return nil;
}

@end
