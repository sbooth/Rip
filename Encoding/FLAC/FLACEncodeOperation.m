/*
 *  Copyright (C) 2007 - 2008 Stephen F. Booth <me@sbooth.org>
 *  All Rights Reserved
 */

#import "FLACEncodeOperation.h"

// ========================================
// KVC key names for the metadata dictionaries
// ========================================
NSString * const	kFLACCompressionLevelKey				= @"FLAC Compression Level";

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
	[arguments addObject:self.inputURL.path];

	// Output file
	[arguments addObject:@"-o"];
	[arguments addObject:self.outputURL.path];

	// Compression level
	NSNumber *compressionLevel = [self.settings objectForKey:kFLACCompressionLevelKey];
	if(compressionLevel)
		[arguments addObject:[NSString stringWithFormat:@"-%i", [compressionLevel integerValue]]];
	
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
	
	// Task setup
	[task setCurrentDirectoryPath:[self.inputURL.path stringByDeletingLastPathComponent]];
	[task setLaunchPath:flacPath];
	[task setArguments:arguments];

	// Run the task
	[task launch];

	while([task isRunning]) {
		
		// Allow the task to be cancelled
		if(self.isCancelled)
			[task terminate];
		
		// Sleep to avoid spinning
		[NSThread sleepUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.25]];
	}
}

@end
