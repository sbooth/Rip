/*
 *  Copyright (C) 2009 Stephen F. Booth <me@sbooth.org>
 *  All Rights Reserved
 */

#import "WavPackEncodeOperation.h"

// ========================================
// KVC key names for the metadata dictionaries
// ========================================
NSString * const	kWavPackCompressionModeKey				= @"compressionMode";
NSString * const	kWavPackComputeMD5Key					= @"computeMD5";

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
		[arguments addObject:@"-w"];
		[arguments addObject:[NSString stringWithFormat:@"\"%@=%@\"", tagName, tagValue]];
	}
}

@implementation WavPackEncodeOperation

- (void) main
{
	NSAssert(nil != self.inputURL, @"self.inputURL may not be nil");
	NSAssert(nil != self.outputURL, @"self.outputURL may not be nil");

	// Locate the wavpack executable
	NSString *wavpackPath = [[NSBundle bundleWithIdentifier:@"org.sbooth.Rip.Encoder.WavPack"] pathForResource:@"wavpack" ofType:nil];
	if(nil == wavpackPath) {
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

	// Compression mode
	NSNumber *compressionMode = [self.settings objectForKey:kWavPackCompressionModeKey];
	if(compressionMode) {
		switch([compressionMode intValue]) {
			case eWavPackCompressionModeFast:		[arguments addObject:@"-f"];	break;
			case eWavPackCompressionModeNormal:										break;
			case eWavPackCompressionModeHigh:		[arguments addObject:@"-h"];	break;
			case eWavPackCompressionModeVeryHigh:	[arguments addObject:@"-hh"];	break;
		}
	}

	// MD5 checksum	
	NSNumber *computeMD5 = [self.settings objectForKey:kWavPackComputeMD5Key];
	if(computeMD5 && [computeMD5 boolValue])
		[arguments addObject:@"-m"];

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
	setArgumentForTag(arguments, self.metadata, kMetadataMusicBrainzIDKey, @"MUSICBRAINZ_ID");

	// Application version
	NSString *appName = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleName"];
	NSString *shortVersionNumber = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleShortVersionString"];
	NSString *versionNumber = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleVersion"];	

	[arguments addObject:@"-w"];
	[arguments addObject:[NSString stringWithFormat:@"\"EXTRACTED_BY=%@ %@ (%@)\"", appName, shortVersionNumber, versionNumber]];

	// Task setup
	[task setCurrentDirectoryPath:[[self.inputURL path] stringByDeletingLastPathComponent]];
	[task setLaunchPath:wavpackPath];
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
}

@end
