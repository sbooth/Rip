/*
 *  Copyright (C) 2008 Stephen F. Booth <me@sbooth.org>
 *  All Rights Reserved
 */

#import "FileUtilities.h"

NSURL *
temporaryURLWithExtension(NSString *extension)
{
	NSCParameterAssert(nil != extension);
	
	// Use the specified temporary directory if it exists, otherwise try the default and fall back to /tmp
	NSString *temporaryDirectory = [[NSUserDefaults standardUserDefaults] stringForKey:@"Temporary Directory"];
	if(!temporaryDirectory)
		temporaryDirectory = NSTemporaryDirectory();
	if(!temporaryDirectory)
		temporaryDirectory = @"/tmp";
	
	// Generate a random filename
	NSString *temporaryFilename = nil;
	do {
		NSString *randomFilename = [NSString stringWithFormat:@"%lx.%@", random(), extension];
		temporaryFilename = [temporaryDirectory stringByAppendingPathComponent:randomFilename];
	} while([[NSFileManager defaultManager] fileExistsAtPath:temporaryFilename]);
	
	return [NSURL fileURLWithPath:temporaryFilename];
}
