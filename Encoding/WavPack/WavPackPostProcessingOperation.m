/*
 *  Copyright (C) 2009 Stephen F. Booth <me@sbooth.org>
 *  All Rights Reserved
 */

#import "WavPackPostProcessingOperation.h"

// ========================================
// The amount of time to sleep while waiting for the NSTask to finish
// ========================================
#define SLEEP_TIME_INTERVAL ((NSTimeInterval)0.25)

@implementation WavPackPostProcessingOperation

- (void) main
{
	NSAssert((nil != self.trackURLs || nil != self.imageURL), @"self.trackURLs and self.imageURL may not be nil");
	
	// Locate the wvgain executable
	NSString *wvgainPath = [[NSBundle bundleWithIdentifier:@"org.sbooth.Rip.Encoder.WavPack"] pathForResource:@"wvgain" ofType:nil];
	if(nil == wvgainPath) {
		self.error = [NSError errorWithDomain:NSOSStatusErrorDomain code:fnfErr userInfo:nil];
		return;
	}
	
	// Create the task
	NSTask *task = [[NSTask alloc] init];
	NSMutableArray *arguments = [NSMutableArray array];

	// ReplayGain scanning
	[arguments addObject:@"-a"];

	// Input files
	if(self.isImage)	
		[arguments addObject:[self.imageURL path]];
	else {
		for(NSURL *trackURL in self.trackURLs)
			[arguments addObject:[trackURL path]];
	}

	// Task setup
	[task setLaunchPath:wvgainPath];
	[task setArguments:arguments];

	// Redirect input and output to /dev/null
#if (!DEBUG)
	[task setStandardOutput:[NSFileHandle fileHandleWithNullDevice]];
	[task setStandardError:[NSFileHandle fileHandleWithNullDevice]];
#endif

	// Run the task
	[task launch];

	while([task isRunning]) {
		
		// Allow the task to be cancelled
		if(self.isCancelled)
			[task terminate];
		
		// Sleep to avoid spinning
		[NSThread sleepForTimeInterval:SLEEP_TIME_INTERVAL];
	}
	
	// Get the result
	int terminationStatus = [task terminationStatus];
	if(EXIT_SUCCESS != terminationStatus)
		self.error = [NSError errorWithDomain:NSPOSIXErrorDomain code:terminationStatus userInfo:nil];
}

@end
