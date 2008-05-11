/*
 *  Copyright (C) 2008 Stephen F. Booth <me@sbooth.org>
 *  All Rights Reserved
 */

#import "EncoderManager.h"
#import "PlugInManager.h"
#import "EncoderInterface/EncoderInterface.h"
#import "EncoderInterface/EncodingOperation.h"

#import "TrackMetadata.h"
#import "AlbumMetadata.h"
#import "TrackDescriptor.h"
#import "SessionDescriptor.h"
#import "CompactDisc.h"
#import "ExtractedTrackRecord.h"
#import "ExtractionRecord.h"

// ========================================
// Flatten the metadata objects into a single NSDictionary
// ========================================
static NSDictionary *
metadataForExtractionRecord(ExtractionRecord *extractionRecord)
{
	NSCParameterAssert(nil != extractionRecord);
	
	NSMutableDictionary *metadata = [NSMutableDictionary dictionary];
	
	// Only a single track was extracted
	if(1 == extractionRecord.tracks.count) {
		TrackMetadata *trackMetadata = extractionRecord.firstTrack.track.metadata;
		AlbumMetadata *albumMetadata = trackMetadata.track.session.disc.metadata;

		// Track number and total
		if(trackMetadata.track.number)
			[metadata setObject:trackMetadata.track.number forKey:kMetadataTrackNumberKey];
		if(trackMetadata.track.session.tracks.count)
			[metadata setObject:[NSNumber numberWithUnsignedInteger:trackMetadata.track.session.tracks.count] forKey:kMetadataTrackTotalKey];
		
		// Album metadata
		if(albumMetadata.artist)
			[metadata setObject:albumMetadata.artist forKey:kMetadataAlbumArtistKey];
		if(albumMetadata.date)
			[metadata setObject:albumMetadata.date forKey:kMetadataReleaseDateKey];
		if(albumMetadata.discNumber)
			[metadata setObject:albumMetadata.discNumber forKey:kMetadataDiscNumberKey];
		if(albumMetadata.discTotal)
			[metadata setObject:albumMetadata.discTotal forKey:kMetadataDiscTotalKey];
		if(albumMetadata.isCompilation)
			[metadata setObject:albumMetadata.isCompilation forKey:kMetadataCompilationKey];
		if(albumMetadata.MCN)
			[metadata setObject:albumMetadata.MCN forKey:kMetadataMCNKey];
		if(albumMetadata.title)
			[metadata setObject:albumMetadata.title forKey:kMetadataAlbumTitleKey];
		
		// Track metadata
		if(trackMetadata.artist)
			[metadata setObject:trackMetadata.artist forKey:kMetadataArtistKey];
		if(trackMetadata.composer)
			[metadata setObject:trackMetadata.composer forKey:kMetadataComposerKey];
		if(trackMetadata.date)
			[metadata setObject:trackMetadata.date forKey:kMetadataReleaseDateKey];
		if(trackMetadata.genre)
			[metadata setObject:trackMetadata.genre forKey:kMetadataGenreKey];
		if(trackMetadata.ISRC)
			[metadata setObject:trackMetadata.ISRC forKey:kMetadataISRCKey];
		if(trackMetadata.title)
			[metadata setObject:trackMetadata.title forKey:kMetadataTitleKey];
	}
	// Multiple tracks were extracted, so fill in album details only
	else {
		TrackMetadata *trackMetadata = extractionRecord.firstTrack.track.metadata;
		AlbumMetadata *albumMetadata = trackMetadata.track.session.disc.metadata;
		
		// Track number and total
		if(trackMetadata.track.session.tracks.count)
			[metadata setObject:[NSNumber numberWithUnsignedInteger:trackMetadata.track.session.tracks.count] forKey:kMetadataTrackTotalKey];
		
		// Album metadata
		if(albumMetadata.artist)
			[metadata setObject:albumMetadata.artist forKey:kMetadataAlbumArtistKey];
		if(albumMetadata.date)
			[metadata setObject:albumMetadata.date forKey:kMetadataReleaseDateKey];
		if(albumMetadata.discNumber)
			[metadata setObject:albumMetadata.discNumber forKey:kMetadataDiscNumberKey];
		if(albumMetadata.discTotal)
			[metadata setObject:albumMetadata.discTotal forKey:kMetadataDiscTotalKey];
		if(albumMetadata.isCompilation)
			[metadata setObject:albumMetadata.isCompilation forKey:kMetadataCompilationKey];
		if(albumMetadata.MCN)
			[metadata setObject:albumMetadata.MCN forKey:kMetadataMCNKey];
		if(albumMetadata.title)
			[metadata setObject:albumMetadata.title forKey:kMetadataAlbumTitleKey];
	}
	
	return metadata;
}

// ========================================
// KVC key names for the encoder dictionaries
// ========================================
NSString * const	kEncoderBundleKey						= @"bundle";
NSString * const	kEncoderSettingsKey						= @"settings";
NSString * const	kEncoderNicknameKey						= @"nickname";
NSString * const	kEncoderSelectedKey						= @"selected";

@implementation EncoderManager

@synthesize queue = _queue;

- (id) init
{
	if((self = [super init]))
		_queue = [[NSOperationQueue alloc] init];
	return self;
}

- (NSArray *) availableEncoders
{
	PlugInManager *plugInManager = [[[NSApplication sharedApplication] delegate] plugInManager];
	
	NSError *error = nil;
	NSArray *availableEncoders = [plugInManager plugInsConformingToProtocol:@protocol(EncoderInterface) error:&error];
	
	return availableEncoders;	
}

- (NSArray *) configuredEncoders
{
	return [[NSUserDefaults standardUserDefaults] arrayForKey:@"configuredEncoders"];
}

- (NSArray *) selectedEncoders
{
	NSPredicate *selectedEncodersPredicate = [NSPredicate predicateWithFormat:@"%K == 1", kEncoderSelectedKey];
	return [self.configuredEncoders filteredArrayUsingPredicate:selectedEncodersPredicate];
}

- (BOOL) encodeURL:(NSURL *)inputURL extractionRecord:(ExtractionRecord *)extractionRecord error:(NSError **)error
{
	NSParameterAssert(nil != inputURL);
	NSParameterAssert(nil != extractionRecord);
	
	PlugInManager *plugInManager = [[[NSApplication sharedApplication] delegate] plugInManager];
//	NSBundle *encoderBundle = [plugInManager plugInForIdentifier:@"org.sbooth.Rip.Encoder.CoreAudio"];
	NSBundle *encoderBundle = [plugInManager plugInForIdentifier:@"org.sbooth.Rip.Encoder.FLAC"];
	
	if(![encoderBundle loadAndReturnError:error])
		return NO;
	
	Class encoderClass = [encoderBundle principalClass];
	NSObject <EncoderInterface> *encoderInterface = [[encoderClass alloc] init];
	
	EncodingOperation *encodingOperation = [encoderInterface encodingOperation];
	
	encodingOperation.inputURL = inputURL;
	NSURL *outputFolderURL = [NSURL fileURLWithPath:[[NSUserDefaults standardUserDefaults] stringForKey:@"outputDirectory"]];
	encodingOperation.outputURL = [NSURL fileURLWithPath:[@"~/Music/fnord.flac" stringByExpandingTildeInPath]];
	encodingOperation.settings = [encoderInterface defaultSettings];
	encodingOperation.metadata = metadataForExtractionRecord(extractionRecord);
	
	[_queue addOperation:encodingOperation];
	
	return YES;
}

@end
