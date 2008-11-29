/*
 *  Copyright (C) 2008 Stephen F. Booth <me@sbooth.org>
 *  All Rights Reserved
 */

#import "AppleLosslessEncodeOperation.h"

@implementation AppleLosslessEncodeOperation

// ========================================
// The amount of time to sleep while waiting for the NSTask to finish
// ========================================
#define SLEEP_TIME_INTERVAL ((NSTimeInterval)0.25)

- (void) main
{
	// The superclass takes care of the encoding
	[super main];
	
	// Stop now if the operation was cancelled or any errors occurred
	if(self.isCancelled || self.error)
		return;
	
	// Locate the AtomicParsley executable
	NSString *apPath = [[NSBundle bundleWithIdentifier:@"org.sbooth.Rip.Encoder.CoreAudio.AppleLossless"] pathForResource:@"AtomicParsley" ofType:nil];
	if(nil == apPath) {
		self.error = [NSError errorWithDomain:NSOSStatusErrorDomain code:fnfErr userInfo:nil];
		return;
	}
	
	// ========================================
	// TAGGING
	
	// Create the task
	NSTask *task = [[NSTask alloc] init];
	NSMutableArray *arguments = [NSMutableArray array];
	
	// The file to tag
	[arguments addObject:[self.outputURL path]];

	// Overwrite the original file
	[arguments addObject:@"--overWrite"];

	// Metadata
	if([self.metadata objectForKey:kMetadataTitleKey]) {
		[arguments addObject:@"--title"];
		[arguments addObject:[self.metadata objectForKey:kMetadataTitleKey]];
	}
	if([self.metadata objectForKey:kMetadataAlbumTitleKey]) {
		[arguments addObject:@"--album"];
		[arguments addObject:[self.metadata objectForKey:kMetadataAlbumTitleKey]];
	}
	if([self.metadata objectForKey:kMetadataArtistKey]) {
		[arguments addObject:@"--artist"];
		[arguments addObject:[self.metadata objectForKey:kMetadataArtistKey]];
	}
	if([self.metadata objectForKey:kMetadataAlbumArtistKey]) {
		[arguments addObject:@"--albumArtist"];
		[arguments addObject:[self.metadata objectForKey:kMetadataAlbumArtistKey]];
	}
	if([self.metadata objectForKey:kMetadataGenreKey]) {
		[arguments addObject:@"--genre"];
		[arguments addObject:[self.metadata objectForKey:kMetadataGenreKey]];
	}
	if([self.metadata objectForKey:kMetadataComposerKey]) {
		[arguments addObject:@"--composer"];
		[arguments addObject:[self.metadata objectForKey:kMetadataComposerKey]];
	}
#if 0
	// FIXME: Determine if release date should be NSDate
	if([self.metadata objectForKey:kMetadataReleaseDateKey]) {
		[arguments addObject:@"--year"];
		[arguments addObject:[self.metadata objectForKey:kMetadataReleaseDateKey]];
	}
#endif
	if([self.metadata objectForKey:kMetadataCompilationKey]) {
		[arguments addObject:@"--compilation"];
		if([[self.metadata objectForKey:kMetadataCompilationKey] boolValue])
			[arguments addObject:@"true"];
		else
			[arguments addObject:@"false"];
	}
	if([self.metadata objectForKey:kMetadataTrackNumberKey]) {
		[arguments addObject:@"--tracknum"];
		if([self.metadata objectForKey:kMetadataTrackTotalKey])
			[arguments addObject:[NSString stringWithFormat:@"%@/%@", [self.metadata objectForKey:kMetadataTrackNumberKey], [self.metadata objectForKey:kMetadataTrackTotalKey]]];
		else
			[arguments addObject:[[self.metadata objectForKey:kMetadataTrackNumberKey] stringValue]];
	}
	if([self.metadata objectForKey:kMetadataDiscNumberKey]) {
		[arguments addObject:@"--disk"];
		if([self.metadata objectForKey:kMetadataDiscTotalKey])
			[arguments addObject:[NSString stringWithFormat:@"%@/%@", [self.metadata objectForKey:kMetadataDiscNumberKey], [self.metadata objectForKey:kMetadataDiscTotalKey]]];
		else
			[arguments addObject:[[self.metadata objectForKey:kMetadataDiscNumberKey] stringValue]];
	}			
	if([self.metadata objectForKey:kMetadataCommentKey]) {
		[arguments addObject:@"--comment"];
		[arguments addObject:[self.metadata objectForKey:kMetadataCommentKey]];
	}
	
	// Task setup
	[task setCurrentDirectoryPath:[[self.outputURL path] stringByDeletingLastPathComponent]];
	[task setLaunchPath:apPath];
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
