/*
 *  Copyright (C) 2008 Stephen F. Booth <me@sbooth.org>
 *  All Rights Reserved
 */

#pragma once

#import <Cocoa/Cocoa.h>

// Generate a URL pointing to a unique temporary file
NSURL * temporaryURLWithExtension(NSString *extension);
