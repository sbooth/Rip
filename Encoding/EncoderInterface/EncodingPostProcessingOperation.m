/*
 *  Copyright (C) 2008 Stephen F. Booth <me@sbooth.org>
 *  All Rights Reserved
 */

#import "EncodingPostProcessingOperation.h"

@implementation EncodingPostProcessingOperation

@synthesize isImage = _isImage;
@synthesize imageURL = _imageURL;
@synthesize imageMetadata = _imageMetadata;
@synthesize cueSheetURL = _cueSheetURL;
@synthesize trackURLs = _trackURLs;
@synthesize trackMetadata = _trackMetadata;
@synthesize settings = _settings;
@synthesize error = _error;

@dynamic progress;

@end
