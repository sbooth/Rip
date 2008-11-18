/*
 *  Copyright (C) 2008 Stephen F. Booth <me@sbooth.org>
 *  All Rights Reserved
 */

#import "FLACPostProcessingOperation.h"

// ========================================
// The amount of time to sleep while waiting for the NSTask to finish
// ========================================
#define SLEEP_TIME_INTERVAL ((NSTimeInterval)0.25)

@implementation FLACPostProcessingOperation

- (void) main
{
	NSAssert(nil != self.URLs, @"self.URLs may not be nil");
	
	// Locate the metaflac executable
	NSString *metaflacPath = [[NSBundle bundleWithIdentifier:@"org.sbooth.Rip.Encoder.FLAC"] pathForResource:@"metaflac" ofType:nil];
	if(nil == metaflacPath) {
		self.error = [NSError errorWithDomain:NSOSStatusErrorDomain code:fnfErr userInfo:nil];
		return;
	}
	
	// ========================================
	// REPLAYGAIN PROCESSING
	
	// Create the task
	NSTask *task = [[NSTask alloc] init];
	NSMutableArray *arguments = [NSMutableArray array];

	// ReplayGain scanning
	[arguments addObject:@"--add-replay-gain"];

	// Input files
	for(NSURL *fileURL in self.URLs)
		[arguments addObject:fileURL.path];
		
	// Task setup
	[task setLaunchPath:metaflacPath];
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
