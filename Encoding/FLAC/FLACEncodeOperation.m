/*
 *  Copyright (C) 2007 - 2009 Stephen F. Booth <me@sbooth.org>
 *  All Rights Reserved
 */

#import "FLACEncodeOperation.h"
#import "FileUtilities.h"
#import "NSImage+BitmapRepresentationMethods.h"

// ========================================
// KVC key names for the metadata dictionaries
// ========================================
NSString * const	kFLACCompressionLevelKey				= @"compressionLevel";

// ========================================
// The amount of time to sleep while waiting for the NSTask to finish
// ========================================
#define SLEEP_TIME_INTERVAL ((NSTimeInterval)0.25)

static void
setArgumentForTag(NSMutableArray *arguments, NSDictionary *metadata, NSString *keyName, NSString *tagName)
{
	NSCParameterAssert(nil != arguments);
	NSCParameterAssert(nil != metadata);
	NSCParameterAssert(nil != keyName);
	NSCParameterAssert(nil != tagName);
	
	NSString *tagValue = [metadata objectForKey:keyName];
	if(tagValue) {
		[arguments addObject:@"-T"];
		[arguments addObject:[NSString stringWithFormat:@"%@=%@", tagName, tagValue]];
	}
}

@implementation FLACEncodeOperation

- (void) main
{
	NSAssert(nil != self.inputURL, @"self.inputURL may not be nil");
	NSAssert(nil != self.outputURL, @"self.outputURL may not be nil");

	// Locate the flac executable
	NSString *flacPath = [[NSBundle bundleWithIdentifier:@"org.sbooth.Rip.Encoder.FLAC"] pathForResource:@"flac" ofType:nil];
	if(nil == flacPath) {
		self.error = [NSError errorWithDomain:NSOSStatusErrorDomain code:fnfErr userInfo:nil];
		return;
	}
	
	// ========================================
	// ENCODING
	
	// Create the task
	NSTask *task = [[NSTask alloc] init];
	NSMutableArray *arguments = [NSMutableArray array];

	// Input file
	[arguments addObject:[self.inputURL path]];

	// Output file
	[arguments addObject:@"-o"];
	[arguments addObject:[self.outputURL path]];

	// Compression level
	NSNumber *compressionLevel = [self.settings objectForKey:kFLACCompressionLevelKey];
	if(compressionLevel)
		[arguments addObject:[NSString stringWithFormat:@"-%i", [compressionLevel integerValue]]];

	// Verify encoding
	[arguments addObject:@"-V"];

	// NSTask doesn't encode text as UTF8, which flac expects
	[arguments addObject:@"--no-utf8-convert"];

	// Metadata
	setArgumentForTag(arguments, self.metadata, kMetadataTitleKey, @"TITLE");
	setArgumentForTag(arguments, self.metadata, kMetadataAlbumTitleKey, @"ALBUM");
	setArgumentForTag(arguments, self.metadata, kMetadataArtistKey, @"ARTIST");
	setArgumentForTag(arguments, self.metadata, kMetadataAlbumArtistKey, @"ALBUMARTIST");
	setArgumentForTag(arguments, self.metadata, kMetadataGenreKey, @"GENRE");
	setArgumentForTag(arguments, self.metadata, kMetadataComposerKey, @"COMPOSER");
	setArgumentForTag(arguments, self.metadata, kMetadataReleaseDateKey, @"DATE");
	setArgumentForTag(arguments, self.metadata, kMetadataCompilationKey, @"COMPILATION");
	setArgumentForTag(arguments, self.metadata, kMetadataTrackNumberKey, @"TRACKNUMBER");
	setArgumentForTag(arguments, self.metadata, kMetadataTrackTotalKey, @"TRACKTOTAL");
	setArgumentForTag(arguments, self.metadata, kMetadataDiscNumberKey, @"DISCNUMBER");
	setArgumentForTag(arguments, self.metadata, kMetadataDiscTotalKey, @"DISCTOTAL");
	setArgumentForTag(arguments, self.metadata, kMetadataCommentKey, @"COMMENT");
	setArgumentForTag(arguments, self.metadata, kMetadataISRCKey, @"ISRC");
	setArgumentForTag(arguments, self.metadata, kMetadataMCNKey, @"MCN");
	setArgumentForTag(arguments, self.metadata, kMetadataMusicBrainzAlbumIDKey, @"MUSICBRAINZ_ALBUMID");
	setArgumentForTag(arguments, self.metadata, kMetadataMusicBrainzTrackIDKey, @"MUSICBRAINZ_TRACKID");
	
	// Replay gain information
	NSNumber *referenceLoudness = [self.metadata objectForKey:kReplayGainReferenceLoudnessKey];
	if(referenceLoudness) {
		[arguments addObject:@"-T"];
		[arguments addObject:[NSString stringWithFormat:@"REPLAYGAIN_REFERENCE_LOUDNESS=%2.1f dB", [referenceLoudness floatValue]]];
	}
	
	NSNumber *trackGain = [self.metadata objectForKey:kReplayGainTrackGainKey];
	if(trackGain) {
		[arguments addObject:@"-T"];
		[arguments addObject:[NSString stringWithFormat:@"REPLAYGAIN_TRACK_GAIN=%+2.2f dB", [trackGain floatValue]]];
	}

	NSNumber *trackPeak = [self.metadata objectForKey:kReplayGainTrackPeakKey];
	if(trackPeak) {
		[arguments addObject:@"-T"];
		[arguments addObject:[NSString stringWithFormat:@"REPLAYGAIN_TRACK_PEAK=%1.8f", [trackPeak floatValue]]];
	}

	NSNumber *albumGain = [self.metadata objectForKey:kReplayGainAlbumGainKey];
	if(albumGain) {
		[arguments addObject:@"-T"];
		[arguments addObject:[NSString stringWithFormat:@"REPLAYGAIN_ALBUM_GAIN=%+2.2f dB", [albumGain floatValue]]];
	}

	NSNumber *albumPeak = [self.metadata objectForKey:kReplayGainAlbumPeakKey];
	if(albumPeak) {
		[arguments addObject:@"-T"];
		[arguments addObject:[NSString stringWithFormat:@"REPLAYGAIN_ALBUM_PEAK=%1.8f", [albumPeak floatValue]]];
	}
	
	// Additional metadata (ie MUSICBRAINZ_SORTORDER)
	NSDictionary *additionalMetadata = [self.metadata objectForKey:kMetadataAdditionalMetadataKey];
	if([additionalMetadata count]) {
		for(NSString *key in [self.metadata objectForKey:kMetadataAdditionalMetadataKey])
			setArgumentForTag(arguments, additionalMetadata, key, key);
	}

	// Application version
	NSString *appName = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleName"];
	NSString *shortVersionNumber = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleShortVersionString"];
	NSString *versionNumber = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleVersion"];	

	[arguments addObject:@"-T"];
	[arguments addObject:[NSString stringWithFormat:@"EXTRACTED_BY=%@ %@ (%@)", appName, shortVersionNumber, versionNumber]];

	// Task setup
	[task setCurrentDirectoryPath:[[self.inputURL path] stringByDeletingLastPathComponent]];
	[task setLaunchPath:flacPath];
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
	if(EXIT_SUCCESS != terminationStatus) {
		self.error = [NSError errorWithDomain:NSPOSIXErrorDomain code:terminationStatus userInfo:nil];
		return;
	}

	// Add album artwork, if present
	if(![self.metadata objectForKey:kAlbumArtFrontCoverKey])
		return;

	// Locate the metaflac executable
	NSString *metaflacPath = [[NSBundle bundleWithIdentifier:@"org.sbooth.Rip.Encoder.FLAC"] pathForResource:@"metaflac" ofType:nil];
	if(nil == metaflacPath) {
		self.error = [NSError errorWithDomain:NSOSStatusErrorDomain code:fnfErr userInfo:nil];
		return;
	}
	
	// Create the task
	task = [[NSTask alloc] init];
	arguments = [NSMutableArray array];

	// Album art
	NSImage *frontCoverImage = [self.metadata objectForKey:kAlbumArtFrontCoverKey];
	NSURL *frontCoverURL = temporaryURLWithExtension(@"png");
	NSData *frontCoverPNGData = [frontCoverImage PNGData];
	[frontCoverPNGData writeToURL:frontCoverURL atomically:NO];
	
	[arguments addObject:[NSString stringWithFormat:@"--import-picture-from=%@", [frontCoverURL path]]];
	
	// Input files
	[arguments addObject:[self.outputURL path]];
	
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
	terminationStatus = [task terminationStatus];
	if(EXIT_SUCCESS != terminationStatus)
		self.error = [NSError errorWithDomain:NSPOSIXErrorDomain code:terminationStatus userInfo:nil];

	// Delete the temporary album art
	NSError *error = nil;
	BOOL removeSuccessful = [[NSFileManager defaultManager] removeItemAtPath:[frontCoverURL path] error:&error];
	if(!removeSuccessful)
		self.error = error;
}

@end
