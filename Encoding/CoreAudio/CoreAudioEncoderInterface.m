/*
 *  Copyright (C) 2008 Stephen F. Booth <me@sbooth.org>
 *  All Rights Reserved
 */

#import "CoreAudioEncoderInterface.h"
#import "CoreAudioEncodeOperation.h"

@implementation CoreAudioEncoderInterface

- (NSString *) encoderName
{
	return NSLocalizedString(@"Core Audio", @"The name of the encoder");
}

- (NSImage *) encoderIcon
{
	return [NSImage imageNamed:@"NSSound"];
}

- (EncodingOperation *) encodingOperation
{
	return [[CoreAudioEncodeOperation alloc] init];
}

@end
