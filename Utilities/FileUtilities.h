/*
 *  Copyright (C) 2008 Stephen F. Booth <me@sbooth.org>
 *  All Rights Reserved
 */

#import <Cocoa/Cocoa.h>

#pragma once

// Generate a URL pointing to a unique temporary file
NSURL * temporaryURLWithExtension(NSString *extension);

// Remove /: characters and replace with _
NSString * makeStringSafeForFilename(NSString *string);
