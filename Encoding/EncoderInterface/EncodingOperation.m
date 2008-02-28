/*
 *  Copyright (C) 2008 Stephen F. Booth <me@sbooth.org>
 *  All Rights Reserved
 */

#import "EncodingOperation.h"

@implementation EncodingOperation

@synthesize inputURL = _inputURL;
@synthesize outputURL = _outputURL;
@synthesize settings = _settings;
@synthesize metadata = _metadata;
@synthesize error = _error;

@dynamic progress;

@end
