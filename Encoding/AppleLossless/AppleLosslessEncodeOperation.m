/*
 *  Copyright (C) 2008 - 2009 Stephen F. Booth <me@sbooth.org>
 *  All Rights Reserved
 */

#import "AppleLosslessEncodeOperation.h"
#import "FileUtilities.h"

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

	// Don't overwrite the original file- save to a temp file and then rename it
	NSURL *taggedURL = temporaryURLWithExtension(@"m4a");

	[arguments addObject:@"-o"];
	[arguments addObject:[taggedURL path]];

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
	if([self.metadata objectForKey:kMetadataReleaseDateKey]) {
		// Attempt to parse the release date
		NSDate *releaseDate = [NSDate dateWithNaturalLanguageString:[self.metadata objectForKey:kMetadataReleaseDateKey]];
		if(releaseDate) {
			NSCalendar *gregorianCalendar = [[NSCalendar alloc] initWithCalendarIdentifier:NSGregorianCalendar];
			NSDateComponents *releaseDateComponents = [gregorianCalendar components:NSYearCalendarUnit fromDate:releaseDate];

			[arguments addObject:@"--year"];
			[arguments addObject:[[NSNumber numberWithInt:[releaseDateComponents year]] stringValue]];
		}		
	}
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
			[arguments addObject:[NSString stringWithFormat:@"%@/%@", [[self.metadata objectForKey:kMetadataTrackNumberKey] stringValue], [[self.metadata objectForKey:kMetadataTrackTotalKey] stringValue]]];
		else
			[arguments addObject:[[self.metadata objectForKey:kMetadataTrackNumberKey] stringValue]];
	}
	if([self.metadata objectForKey:kMetadataDiscNumberKey]) {
		[arguments addObject:@"--disk"];
		if([self.metadata objectForKey:kMetadataDiscTotalKey])
			[arguments addObject:[NSString stringWithFormat:@"%@/%@", [[self.metadata objectForKey:kMetadataDiscNumberKey] stringValue], [[self.metadata objectForKey:kMetadataDiscTotalKey] stringValue]]];
		else
			[arguments addObject:[[self.metadata objectForKey:kMetadataDiscNumberKey] stringValue]];
	}			
	if([self.metadata objectForKey:kMetadataCommentKey]) {
		[arguments addObject:@"--comment"];
		[arguments addObject:[self.metadata objectForKey:kMetadataCommentKey]];
	}
	if([self.metadata objectForKey:kAlbumArtFrontCoverKey]) {
		[arguments addObject:@"--artwork"];
		NSURL *frontCoverURL = [self.metadata objectForKey:kAlbumArtFrontCoverKey];
		[arguments addObject:[frontCoverURL path]];
	}
	
	// Application version
	NSString *appName = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleName"];
	NSString *shortVersionNumber = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleShortVersionString"];
	NSString *versionNumber = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleVersion"];	
	
	[arguments addObject:@"--encodingTool"];
	[arguments addObject:[NSString stringWithFormat:@"%@ %@ (%@)", appName, shortVersionNumber, versionNumber]];

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
	// If successful, delete the untagged file and replace it with the tagged version
	else {
		NSError *error = nil;
		BOOL removeSuccessful = [[NSFileManager defaultManager] removeItemAtPath:[self.outputURL path] error:&error];
		if(removeSuccessful) {
			BOOL renameSuccessful = [[NSFileManager defaultManager] moveItemAtPath:[taggedURL path] toPath:[self.outputURL path] error:&error];
			if(!renameSuccessful)
				self.error = error;
		}
		else
			self.error = error;
	}
}

@end
