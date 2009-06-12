/*
 *  Copyright (C) 2008 - 2009 Stephen F. Booth <me@sbooth.org>
 *  All Rights Reserved
 */

#import "EncoderManager.h"
#import "PlugInManager.h"
#import "EncoderInterface/EncoderInterface.h"
#import "EncoderInterface/EncodingOperation.h"

#import "CompactDisc.h"
#import "CompactDisc+CueSheetGeneration.h"
#import "SessionDescriptor.h"
#import "TrackDescriptor.h"

#import "AlbumMetadata.h"
#import "AlbumArtwork.h"
#import "TrackMetadata.h"

#import "TrackExtractionRecord.h"
#import "ImageExtractionRecord.h"

#import "NSImage+BitmapRepresentationMethods.h"
#import "NSString+PathSanitizationMethods.h"

#import "FileUtilities.h"
#import "Logger.h"

// ========================================
// Flatten the metadata objects into a single NSDictionary
// ========================================
static NSDictionary *
metadataForTrackExtractionRecord(TrackExtractionRecord *trackExtractionRecord)
{
	NSCParameterAssert(nil != trackExtractionRecord);
	
	NSMutableDictionary *metadata = [NSMutableDictionary dictionary];
	
	// Only a single track was extracted
	TrackMetadata *trackMetadata = trackExtractionRecord.track.metadata;
	AlbumMetadata *albumMetadata = trackMetadata.track.session.disc.metadata;

	NSMutableDictionary *additionalMetadata = [NSMutableDictionary dictionary];
	
	// Track number and total
	if(trackMetadata.track.number)
		[metadata setObject:trackMetadata.track.number forKey:kMetadataTrackNumberKey];
	if(trackMetadata.track.session.tracks.count)
		[metadata setObject:[NSNumber numberWithUnsignedInteger:trackMetadata.track.session.tracks.count] forKey:kMetadataTrackTotalKey];
	
	// Album metadata
	if(albumMetadata.additionalMetadata)
		[additionalMetadata addEntriesFromDictionary:albumMetadata.additionalMetadata];
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
	if(albumMetadata.musicBrainzID)
		[metadata setObject:albumMetadata.musicBrainzID forKey:kMetadataMusicBrainzAlbumIDKey];
	if(albumMetadata.peak)
		[metadata setObject:albumMetadata.peak forKey:kReplayGainAlbumPeakKey];
	if(albumMetadata.replayGain)
		[metadata setObject:albumMetadata.replayGain forKey:kReplayGainAlbumGainKey];
	if(albumMetadata.title)
		[metadata setObject:albumMetadata.title forKey:kMetadataAlbumTitleKey];
	[metadata setObject:[NSNumber numberWithFloat:89.f] forKey:kReplayGainReferenceLoudnessKey];

	// Album artwork
	NSImage *frontCoverImage = albumMetadata.artwork.frontCoverImage;
	if(frontCoverImage)
		[metadata setObject:frontCoverImage forKey:kAlbumArtFrontCoverKey];

	// Track metadata
	if(trackMetadata.additionalMetadata)
		[additionalMetadata addEntriesFromDictionary:trackMetadata.additionalMetadata];
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
	if(trackMetadata.musicBrainzID)
		[metadata setObject:trackMetadata.musicBrainzID forKey:kMetadataMusicBrainzTrackIDKey];
	if(trackMetadata.peak)
		[metadata setObject:trackMetadata.peak forKey:kReplayGainTrackPeakKey];
	if(trackMetadata.replayGain)
		[metadata setObject:trackMetadata.replayGain forKey:kReplayGainTrackGainKey];
	if(trackMetadata.title)
		[metadata setObject:trackMetadata.title forKey:kMetadataTitleKey];

	if([additionalMetadata count])
		[metadata setObject:[additionalMetadata copy] forKey:kMetadataAdditionalMetadataKey];
	
	return [metadata copy];
}

static NSDictionary *
metadataForImageExtractionRecord(ImageExtractionRecord *imageExtractionRecord)
{
	NSCParameterAssert(nil != imageExtractionRecord);
	
	NSMutableDictionary *metadata = [NSMutableDictionary dictionary];

	// Multiple tracks were extracted
	AlbumMetadata *albumMetadata = imageExtractionRecord.disc.metadata;
	
	// Track total
	[metadata setObject:[NSNumber numberWithUnsignedInteger:imageExtractionRecord.tracks.count] forKey:kMetadataTrackTotalKey];
	
	// Album metadata
	if(albumMetadata.additionalMetadata)
		[metadata setObject:albumMetadata.additionalMetadata forKey:kMetadataAdditionalMetadataKey];
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
	if(albumMetadata.musicBrainzID)
		[metadata setObject:albumMetadata.musicBrainzID forKey:kMetadataMusicBrainzAlbumIDKey];
	if(albumMetadata.peak)
		[metadata setObject:albumMetadata.peak forKey:kReplayGainAlbumPeakKey];
	if(albumMetadata.replayGain)
		[metadata setObject:albumMetadata.replayGain forKey:kReplayGainAlbumGainKey];
	if(albumMetadata.title)
		[metadata setObject:albumMetadata.title forKey:kMetadataAlbumTitleKey];
	[metadata setObject:[NSNumber numberWithFloat:89.f] forKey:kReplayGainReferenceLoudnessKey];

	// Cue sheet
	[metadata setObject:[imageExtractionRecord.disc cueSheetString] forKey:kCueSheetKey];
	
	// Album artwork
	NSImage *frontCoverImage = albumMetadata.artwork.frontCoverImage;
	if(frontCoverImage)
		[metadata setObject:frontCoverImage forKey:kAlbumArtFrontCoverKey];

	// Individual track metadata
	NSMutableArray *trackMetadataArray = [NSMutableArray array];
	for(TrackExtractionRecord *trackExtractionRecord in imageExtractionRecord.tracks) {
		NSDictionary *trackMetadata = metadataForTrackExtractionRecord(trackExtractionRecord);
		[trackMetadataArray addObject:trackMetadata];
	}
	[metadata setObject:trackMetadataArray forKey:kTrackMetadataArrayKey];
	
	return [metadata copy];
}

// ========================================
// Create the output filename to use for the given ExtractionRecord
// ========================================
static NSString *
defaultFilenameForTrackExtractionRecord(TrackExtractionRecord *trackExtractionRecord)
{
	NSCParameterAssert(nil != trackExtractionRecord);
	
	// Only a single track was extracted
	TrackDescriptor *track = trackExtractionRecord.track;
	
	NSString *title = track.metadata.title;
	if(nil == title)
		title = NSLocalizedString(@"Unknown Title", @"");
	
	// Build up the sanitized track name
	return [NSString stringWithFormat:@"%02lu %@", track.number.unsignedIntegerValue, [title stringByReplacingIllegalPathCharactersWithString:@"_"]];
}

static NSString *
customFilenameForTrackExtractionRecord(TrackExtractionRecord *trackExtractionRecord)
{
	NSCParameterAssert(nil != trackExtractionRecord);
	
	NSString *format = [[NSUserDefaults standardUserDefaults] stringForKey:@"customOutputFileNamingFormat"];
	NSMutableString *path = [[format lastPathComponent] mutableCopy];
	
	// Flesh out the album metadata, substituting as required
	AlbumMetadata *albumMetadata = trackExtractionRecord.track.session.disc.metadata;
	
	NSString *albumTitle = albumMetadata.title ? albumMetadata.title : @"";
	[path replaceOccurrencesOfString:@"{albumTitle}" withString:albumTitle options:0 range:NSMakeRange(0, [path length])];
	
	NSString *albumArtist = albumMetadata.artist ? albumMetadata.artist : @"";
	[path replaceOccurrencesOfString:@"{albumArtist}" withString:albumArtist options:0 range:NSMakeRange(0, [path length])];
	
	NSString *albumDate = albumMetadata.date ? albumMetadata.date : @"";
	[path replaceOccurrencesOfString:@"{albumDate}" withString:albumDate options:0 range:NSMakeRange(0, [path length])];
	
	NSString *discNumber = albumMetadata.discNumber ? [NSString stringWithFormat:@"%02lu", [albumMetadata.discNumber unsignedIntegerValue]] : @"";
	[path replaceOccurrencesOfString:@"{discNumber}" withString:discNumber options:0 range:NSMakeRange(0, [path length])];
	
	NSString *discTotal = albumMetadata.discTotal ? [NSString stringWithFormat:@"%02lu", [albumMetadata.discTotal unsignedIntegerValue]] : @"";
	[path replaceOccurrencesOfString:@"{discTotal}" withString:discTotal options:0 range:NSMakeRange(0, [path length])];

	// Do the same for the track metadata
	TrackMetadata *trackMetadata = trackExtractionRecord.track.metadata;

	NSString *trackTitle = trackMetadata.title ? trackMetadata.title : @"";
	[path replaceOccurrencesOfString:@"{trackTitle}" withString:trackTitle options:0 range:NSMakeRange(0, [path length])];
	
	NSString *trackArtist = trackMetadata.artist ? trackMetadata.artist : @"";
	[path replaceOccurrencesOfString:@"{trackArtist}" withString:trackArtist options:0 range:NSMakeRange(0, [path length])];
	
	NSString *trackDate = trackMetadata.date ? trackMetadata.date : @"";
	[path replaceOccurrencesOfString:@"{trackDate}" withString:trackDate options:0 range:NSMakeRange(0, [path length])];

	NSString *trackGenre = trackMetadata.genre ? trackMetadata.genre : @"";
	[path replaceOccurrencesOfString:@"{trackGenre}" withString:trackGenre options:0 range:NSMakeRange(0, [path length])];

	NSString *trackComposer = trackMetadata.composer ? trackMetadata.composer : @"";
	[path replaceOccurrencesOfString:@"{trackComposer}" withString:trackComposer options:0 range:NSMakeRange(0, [path length])];

	NSString *trackNumber = trackExtractionRecord.track.number ? [NSString stringWithFormat:@"%02lu", [trackExtractionRecord.track.number unsignedIntegerValue]] : @"";
	[path replaceOccurrencesOfString:@"{trackNumber}" withString:trackNumber options:0 range:NSMakeRange(0, [path length])];
	
	NSString *trackTotal = [trackExtractionRecord.track.session.tracks count] ? [NSString stringWithFormat:@"%02lu", [trackExtractionRecord.track.session.tracks count]] : @"";
	[path replaceOccurrencesOfString:@"{trackTotal}" withString:trackTotal options:0 range:NSMakeRange(0, [path length])];
	
	// Don't allow any illegal characters
	[path replaceIllegalPathCharactersWithString:@"_"];
	
	return [path copy];
}

static NSString *
filenameForTrackExtractionRecord(TrackExtractionRecord *trackExtractionRecord)
{
	NSCParameterAssert(nil != trackExtractionRecord);
		
	if([[NSUserDefaults standardUserDefaults] boolForKey:@"useCustomOutputFileNaming"])
		return customFilenameForTrackExtractionRecord(trackExtractionRecord);
	else
		return defaultFilenameForTrackExtractionRecord(trackExtractionRecord);
}

static NSString *
defaultFilenameForImageExtractionRecord(ImageExtractionRecord *imageExtractionRecord)
{
	NSCParameterAssert(nil != imageExtractionRecord);
	
	NSString *filename = nil;
	CompactDisc *disc = imageExtractionRecord.disc;
	NSString *title = disc.metadata.title;
	if(nil == title)
		title = NSLocalizedString(@"Unknown Album", @"");
	
	// Build up the sanitized file name
	if(imageExtractionRecord.tracks.count != disc.firstSession.tracks.count) {
		TrackExtractionRecord *firstTrack = imageExtractionRecord.firstTrack;
		TrackExtractionRecord *lastTrack = imageExtractionRecord.lastTrack;
		
		filename = [NSString stringWithFormat:@"%@ (%@ - %@)", [title stringByReplacingIllegalPathCharactersWithString:@"_"], firstTrack.track.number, lastTrack.track.number];
	}
	else
		filename = [title stringByReplacingIllegalPathCharactersWithString:@"_"];
	
	return filename;
}

static NSString *
customFilenameForImageExtractionRecord(ImageExtractionRecord *imageExtractionRecord)
{
	NSCParameterAssert(nil != imageExtractionRecord);
	
	NSString *format = [[NSUserDefaults standardUserDefaults] stringForKey:@"customOutputFileNamingFormat"];
	NSMutableString *path = [[format lastPathComponent] mutableCopy];
	
	// Flesh out the album metadata, substituting as required
	AlbumMetadata *albumMetadata = imageExtractionRecord.disc.metadata;
	
	NSString *albumTitle = albumMetadata.title ? albumMetadata.title : @"";
	[path replaceOccurrencesOfString:@"{albumTitle}" withString:albumTitle options:0 range:NSMakeRange(0, [path length])];
	
	NSString *albumArtist = albumMetadata.artist ? albumMetadata.artist : @"";
	[path replaceOccurrencesOfString:@"{albumArtist}" withString:albumArtist options:0 range:NSMakeRange(0, [path length])];
	
	NSString *albumDate = albumMetadata.date ? albumMetadata.date : @"";
	[path replaceOccurrencesOfString:@"{albumDate}" withString:albumDate options:0 range:NSMakeRange(0, [path length])];
	
	NSString *discNumber = albumMetadata.discNumber ? [NSString stringWithFormat:@"%02lu", [albumMetadata.discNumber unsignedIntegerValue]] : @"";
	[path replaceOccurrencesOfString:@"{discNumber}" withString:discNumber options:0 range:NSMakeRange(0, [path length])];
	
	NSString *discTotal = albumMetadata.discTotal ? [NSString stringWithFormat:@"%02lu", [albumMetadata.discTotal unsignedIntegerValue]] : @"";
	[path replaceOccurrencesOfString:@"{discTotal}" withString:discTotal options:0 range:NSMakeRange(0, [path length])];
		
	// Don't allow any illegal characters
	[path replaceIllegalPathCharactersWithString:@"_"];
	
	return [path copy];
}

static NSString *
filenameForImageExtractionRecord(ImageExtractionRecord *imageExtractionRecord)
{
	NSCParameterAssert(nil != imageExtractionRecord);
	
	if([[NSUserDefaults standardUserDefaults] boolForKey:@"useCustomOutputFileNaming"])
		return customFilenameForImageExtractionRecord(imageExtractionRecord);
	else
		return defaultFilenameForImageExtractionRecord(imageExtractionRecord);
}

// ========================================
// Sorting function for sorting bundles by encoder names
// ========================================
static NSComparisonResult
encoderBundleSortFunction(id bundleA, id bundleB, void *context)
{
	
#pragma unused(context)
	
	NSCParameterAssert(nil != bundleA);
	NSCParameterAssert(nil != bundleB);
	NSCParameterAssert([bundleA isKindOfClass:[NSBundle class]]);
	NSCParameterAssert([bundleB isKindOfClass:[NSBundle class]]);
	
	NSString *bundleAName = [bundleA objectForInfoDictionaryKey:@"EncoderName"];
	NSString *bundleBName = [bundleB objectForInfoDictionaryKey:@"EncoderName"];

	return [bundleAName compare:bundleBName];
}

// ========================================
// Context objects for observeValueForKeyPath:ofObject:change:context:
// ========================================
static NSString * const kEncodingOperationKVOContext					= @"org.sbooth.Rip.EncoderManager.EncodingOperationKVOContext";

// ========================================
// KVC key names for the encoder dictionaries
// ========================================
NSString * const	kEncoderBundleKey						= @"bundle";
NSString * const	kEncoderSettingsKey						= @"settings";

// ========================================
// Static variables
// ========================================
static EncoderManager *sSharedEncoderManager				= nil;

@interface EncoderManager (Private)
- (NSURL *) outputURLForBaseURL:(NSURL *)baseURL filename:(NSString *)filename pathExtension:(NSString *)pathExtension error:(NSError **)error;
- (NSString *) standardPathnameForCompactDisc:(CompactDisc *)disc;
- (NSString *) customPathnameForCompactDisc:(CompactDisc *)disc;
@end

@implementation EncoderManager

@synthesize queue = _queue;

+ (id) sharedEncoderManager
{
	if(!sSharedEncoderManager)
		sSharedEncoderManager = [[self alloc] init];
	return sSharedEncoderManager;
}

+ (NSSet *) keyPathsForValuesAffectingDefaultEncoderSettings
{
	return [NSSet setWithObject:@"defaultEncoder"];
}

- (id) init
{
	if((self = [super init]))
		_queue = [[NSOperationQueue alloc] init];
	return self;
}

- (void) observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context
{
	if(kEncodingOperationKVOContext == context) {
		EncodingOperation *operation = (EncodingOperation *)object;
		
		if([keyPath isEqualToString:@"isCancelled"] || [keyPath isEqualToString:@"isFinished"]) {
			[operation removeObserver:self forKeyPath:@"isCancelled"];
			[operation removeObserver:self forKeyPath:@"isFinished"];
			
			// Remove the temporary file
			NSError *error = nil;
			NSFileManager *fileManager = [NSFileManager defaultManager];
			if([fileManager fileExistsAtPath:[operation.inputURL path]] && ![fileManager removeItemAtPath:[operation.inputURL path] error:&error])
				[[NSApplication sharedApplication] presentError:error];
		}
	}
	else
		[super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
}

- (NSArray *) availableEncoders
{
	PlugInManager *plugInManager = [PlugInManager sharedPlugInManager];
	
	NSError *error = nil;
	NSArray *availableEncoders = [plugInManager plugInsConformingToProtocol:@protocol(EncoderInterface) error:&error];
	
	return [availableEncoders sortedArrayUsingFunction:encoderBundleSortFunction context:NULL];
}

- (NSBundle *) defaultEncoder
{
	NSString *bundleIdentifier = [[NSUserDefaults standardUserDefaults] stringForKey:@"defaultEncoder"];
	NSBundle *bundle = [[PlugInManager sharedPlugInManager] plugInForIdentifier:bundleIdentifier];
	
	// If the default wasn't found, return any available encoder
	if(!bundle)
		bundle = [self.availableEncoders lastObject];
	
	return bundle;
}

- (void) setDefaultEncoder:(NSBundle *)encoder
{
	NSParameterAssert(nil != encoder);
	
	// Verify this is a valid encoder
	if(![self.availableEncoders containsObject:encoder])
		return;
	
	[self willChangeValueForKey:@"settingsForDefaultMusicDatabase"];

	// Set this as the default encoder
	NSString *bundleIdentifier = [encoder bundleIdentifier];
	[[NSUserDefaults standardUserDefaults] setObject:bundleIdentifier forKey:@"defaultEncoder"];
	
	// If no settings are present for this encoder, store the defaults
	if(![[NSUserDefaults standardUserDefaults] dictionaryForKey:bundleIdentifier]) {
		// Instantiate the encoder interface
		id <EncoderInterface> encoderInterface = [[[encoder principalClass] alloc] init];
		
		// Grab the encoder's settings dictionary
		[[NSUserDefaults standardUserDefaults] setObject:[encoderInterface defaultSettings] forKey:bundleIdentifier];
	}
}

- (NSDictionary *) defaultEncoderSettings
{
	return [self settingsForEncoder:self.defaultEncoder];
}

- (void) setDefaultEncoderSettings:(NSDictionary *)encoderSettings
{
	[self storeSettings:encoderSettings forEncoder:self.defaultEncoder];
}

- (eExistingOutputFileHandling) existingOutputFileHandling
{
	return [[NSUserDefaults standardUserDefaults] integerForKey:@"existingOutputFileHandling"];
}

- (void) setExistingOutputFileHandling:(eExistingOutputFileHandling)outputFileHandling
{
	[[NSUserDefaults standardUserDefaults] setInteger:outputFileHandling forKey:@"existingOutputFileHadling"];
}

- (NSDictionary *) settingsForEncoder:(NSBundle *)encoder
{
	NSParameterAssert(nil != encoder);
	
	// Verify this is a valid encoder
	if(![self.availableEncoders containsObject:encoder])
		return nil;
	
	NSString *bundleIdentifier = [encoder bundleIdentifier];
	NSDictionary *encoderSettings = [[NSUserDefaults standardUserDefaults] dictionaryForKey:bundleIdentifier];
	
	// If no settings are present for this encoder, use the defaults
	if(!encoderSettings) {
		// Instantiate the encoder interface
		id <EncoderInterface> encoderInterface = [[[encoder principalClass] alloc] init];
		
		// Grab the encoder's settings dictionary
		encoderSettings = [encoderInterface defaultSettings];
		
		// Store the defaults
		if(encoderSettings)
			[[NSUserDefaults standardUserDefaults] setObject:encoderSettings forKey:bundleIdentifier];
	}
	
	return [encoderSettings copy];
}

- (void) storeSettings:(NSDictionary *)encoderSettings forEncoder:(NSBundle *)encoder
{

	NSParameterAssert(nil != encoder);
	
	// Verify this is a valid encoder
	if(![self.availableEncoders containsObject:encoder])
		return;
	
	NSString *bundleIdentifier = [encoder bundleIdentifier];
	if(encoderSettings)
		[[NSUserDefaults standardUserDefaults] setObject:encoderSettings forKey:bundleIdentifier];
	else
		[[NSUserDefaults standardUserDefaults] removeObjectForKey:bundleIdentifier];
}

- (void) restoreDefaultSettingsForEncoder:(NSBundle *)encoder
{
	NSParameterAssert(nil != encoder);
	
	// Verify this is a valid encoder
	if(![self.availableEncoders containsObject:encoder])
		return;
	
	NSString *bundleIdentifier = [encoder bundleIdentifier];

	// Instantiate the encoder interface
	id <EncoderInterface> encoderInterface = [[[encoder principalClass] alloc] init];
	
	// Grab the encoder's settings dictionary
	NSDictionary *encoderSettings = [encoderInterface defaultSettings];
	
	// Store the defaults
	if(encoderSettings)
		[[NSUserDefaults standardUserDefaults] setObject:encoderSettings forKey:bundleIdentifier];
	else
		[[NSUserDefaults standardUserDefaults] removeObjectForKey:bundleIdentifier];
}

- (NSURL *) outputURLForCompactDisc:(CompactDisc *)disc
{
	NSParameterAssert(nil != disc);

	// Create the pathname
	NSString *pathForCompactDisc = nil;
	if([[NSUserDefaults standardUserDefaults] boolForKey:@"useCustomOutputFileNaming"])
		pathForCompactDisc = [self customPathnameForCompactDisc:disc];
	else
		pathForCompactDisc = [self standardPathnameForCompactDisc:disc];

	// Append it to the output folder
	NSURL *outputFolderURL = [NSUnarchiver unarchiveObjectWithData:[[NSUserDefaults standardUserDefaults] dataForKey:@"outputDirectory"]];
	NSString *outputPath = [[outputFolderURL path] stringByAppendingPathComponent:pathForCompactDisc];
	
	return [NSURL fileURLWithPath:outputPath];
}

- (BOOL) encodeTrackExtractionRecord:(TrackExtractionRecord *)trackExtractionRecord error:(NSError **)error
{
	return [self encodeTrackExtractionRecord:trackExtractionRecord encodingOperation:NULL error:error];
}

- (BOOL) encodeTrackExtractionRecord:(TrackExtractionRecord *)trackExtractionRecord encodingOperation:(EncodingOperation **)encodingOperation error:(NSError **)error
{
	NSParameterAssert(nil != trackExtractionRecord);
	NSParameterAssert(nil != trackExtractionRecord.inputURL);
	
	NSBundle *encoderBundle = [self defaultEncoder];	
	if(![encoderBundle loadAndReturnError:error])
		return NO;
	
	NSDictionary *encoderSettings = [self settingsForEncoder:encoderBundle];
	
	Class encoderClass = [encoderBundle principalClass];
	NSObject <EncoderInterface> *encoderInterface = [[encoderClass alloc] init];
	
	// Build the filename for the output from the disc's folder, the track's name and number,
	// and the encoder's output path extension
	NSURL *baseURL = [self outputURLForCompactDisc:trackExtractionRecord.track.session.disc];
	NSString *filename = filenameForTrackExtractionRecord(trackExtractionRecord);
	NSString *pathExtension = [encoderInterface pathExtensionForSettings:encoderSettings];
	
	// Ensure the output folder exists
	if(![[NSFileManager defaultManager] createDirectoryAtPath:[baseURL path] withIntermediateDirectories:YES attributes:nil error:error])
		return NO;
	
	NSURL *outputURL = [self outputURLForBaseURL:baseURL filename:filename pathExtension:pathExtension error:error];
	if(nil == outputURL)
		return NO;
	
	EncodingOperation *operation = [encoderInterface encodingOperation];
	if(!operation)
		return NO;
	
	operation.inputURL = trackExtractionRecord.inputURL;
	operation.outputURL = outputURL;
	operation.settings = encoderSettings;
	operation.metadata = metadataForTrackExtractionRecord(trackExtractionRecord);
	
	[[Logger sharedLogger] logMessageWithLevel:eLogMessageLevelDebug format:@"Encoding %@ to %@ using %@", [operation.inputURL path], [operation.outputURL path], [encoderBundle objectForInfoDictionaryKey:@"EncoderName"]];

	// Observe the operation's progress so the input file can be deleted when it completes
	[operation addObserver:self forKeyPath:@"isCancelled" options:NSKeyValueObservingOptionNew context:kEncodingOperationKVOContext];
	[operation addObserver:self forKeyPath:@"isFinished" options:NSKeyValueObservingOptionNew context:kEncodingOperationKVOContext];
	
	[self.queue addOperation:operation];
	
	// Communicate the output URL back to the caller
	trackExtractionRecord.outputURL = operation.outputURL;
	
	if(encodingOperation)
		*encodingOperation = operation;
	
	return YES;
}

- (BOOL) encodeImageExtractionRecord:(ImageExtractionRecord *)imageExtractionRecord error:(NSError **)error
{
	return [self encodeImageExtractionRecord:imageExtractionRecord encodingOperation:NULL error:error];
}

- (BOOL) encodeImageExtractionRecord:(ImageExtractionRecord *)imageExtractionRecord encodingOperation:(EncodingOperation **)encodingOperation error:(NSError **)error
{
	NSParameterAssert(nil != imageExtractionRecord);
	NSParameterAssert(nil != imageExtractionRecord.inputURL);
	
	NSBundle *encoderBundle = [self defaultEncoder];	
	if(![encoderBundle loadAndReturnError:error])
		return NO;
	
	NSDictionary *encoderSettings = [self settingsForEncoder:encoderBundle];
	
	Class encoderClass = [encoderBundle principalClass];
	NSObject <EncoderInterface> *encoderInterface = [[encoderClass alloc] init];
	
	// Build the filename for the output from the disc's folder, the track's name and number,
	// and the encoder's output path extension
	NSURL *baseURL = [self outputURLForCompactDisc:imageExtractionRecord.disc];
	NSString *filename = filenameForImageExtractionRecord(imageExtractionRecord);
	NSString *pathExtension = [encoderInterface pathExtensionForSettings:encoderSettings];
	
	// Ensure the output folder exists
	if(![[NSFileManager defaultManager] createDirectoryAtPath:[baseURL path] withIntermediateDirectories:YES attributes:nil error:error])
		return NO;
	
	NSURL *outputURL = [self outputURLForBaseURL:baseURL filename:filename pathExtension:pathExtension error:error];
	if(nil == outputURL)
		return NO;	
	
	EncodingOperation *operation = [encoderInterface encodingOperation];
	if(!operation)
		return NO;
	
	operation.inputURL = imageExtractionRecord.inputURL;
	operation.outputURL = outputURL;
	operation.settings = encoderSettings;
	operation.metadata = metadataForImageExtractionRecord(imageExtractionRecord);

	[[Logger sharedLogger] logMessageWithLevel:eLogMessageLevelDebug format:@"Encoding %@ to %@ using %@", [operation.inputURL path], [operation.outputURL path], [encoderBundle objectForInfoDictionaryKey:@"EncoderName"]];
	
	// Observe the operation's progress so the input file can be deleted when it completes
	[operation addObserver:self forKeyPath:@"isCancelled" options:NSKeyValueObservingOptionNew context:kEncodingOperationKVOContext];
	[operation addObserver:self forKeyPath:@"isFinished" options:NSKeyValueObservingOptionNew context:kEncodingOperationKVOContext];

	[self.queue addOperation:operation];
		
	// Communicate the output URL back to the caller
	imageExtractionRecord.outputURL = operation.outputURL;
	
	if(encodingOperation)
		*encodingOperation = operation;
	
	return YES;
}

@end

@implementation EncoderManager (Private)

- (NSURL *) outputURLForBaseURL:(NSURL *)baseURL filename:(NSString *)filename pathExtension:(NSString *)pathExtension error:(NSError **)error
{
	NSParameterAssert(nil != baseURL);
	NSParameterAssert(nil != filename);
	NSParameterAssert(nil != pathExtension);
	
	NSString *pathname = [filename stringByAppendingPathExtension:pathExtension];
	NSString *outputPath = [[baseURL path] stringByAppendingPathComponent:pathname];
	
	// Handle existing output files
	if([[NSFileManager defaultManager] fileExistsAtPath:outputPath]) {
		eExistingOutputFileHandling existingOutputFileBehavior = [self existingOutputFileHandling];
		
		if(eExistingOutputFileHandlingOverwrite == existingOutputFileBehavior) {
			if(![[NSFileManager defaultManager] removeItemAtPath:outputPath error:error])
				return nil;
		}
		else if(eExistingOutputFileHandlingRename == existingOutputFileBehavior) {
			NSString *backupFilename = [filename copy];
			NSString *backupPathname = nil;
			NSString *backupPath = nil;
			
			do {
				backupFilename = [backupFilename stringByAppendingPathExtension:@"old"];
				backupPathname = [backupFilename stringByAppendingPathExtension:pathExtension];
				backupPath = [[baseURL path] stringByAppendingPathComponent:backupPathname];
			} while([[NSFileManager defaultManager] fileExistsAtPath:backupPath]);
			
			if(![[NSFileManager defaultManager] movePath:outputPath toPath:backupPath handler:nil])
				return nil;
		}
		else if(eExistingOutputFileHandlingAsk == existingOutputFileBehavior) {
			NSInteger alertReturn = NSRunAlertPanel([NSString stringWithFormat:NSLocalizedString(@"The file \u201c%@\u201d exists. Would you like to rename it?", @""), [outputPath lastPathComponent]], 
													NSLocalizedString(@"If you select overwrite the file will be permanently deleted.", @""), 
													NSLocalizedString(@"Rename", @"Button"), 
													NSLocalizedString(@"Overwrite", @"Button"), 
													NSLocalizedString(@"Cancel", @"Button"));
			if(NSAlertDefaultReturn == alertReturn) {
				NSString *backupFilename = [filename copy];
				NSString *backupPathname = nil;
				NSString *backupPath = nil;
				
				do {
					backupFilename = [backupFilename stringByAppendingPathExtension:@"old"];
					backupPathname = [backupFilename stringByAppendingPathExtension:pathExtension];
					backupPath = [[baseURL path] stringByAppendingPathComponent:backupPathname];
				} while([[NSFileManager defaultManager] fileExistsAtPath:backupPath]);
				
				if(![[NSFileManager defaultManager] movePath:outputPath toPath:backupPath handler:nil])
					return nil;
			}
			else if(NSAlertAlternateReturn == alertReturn) {
				if(![[NSFileManager defaultManager] removeItemAtPath:outputPath error:error])
					return nil;
			}
			else if(NSAlertOtherReturn == alertReturn) {
				if(error)
					*error = [NSError errorWithDomain:NSPOSIXErrorDomain code:EEXIST userInfo:nil];
				return nil;
			}
		}
		// The default is to preserve existing files
		else {
			if(error)
				*error = [NSError errorWithDomain:NSPOSIXErrorDomain code:EEXIST userInfo:nil];
			return nil;
		}
	}
	
	return [NSURL fileURLWithPath:outputPath];
}

- (NSString *) standardPathnameForCompactDisc:(CompactDisc *)disc
{
	NSParameterAssert(nil != disc);
	
	NSString *title = disc.metadata.title;
	if(nil == title)
		title = NSLocalizedString(@"Unknown Album", @"");
	
	NSString *artist = disc.metadata.artist;
	if(nil == artist)
		artist = NSLocalizedString(@"Unknown Artist", @"");
	
	// Build up the sanitized Artist/Album structure
	NSArray *pathComponents = [NSArray arrayWithObjects:[artist stringByReplacingIllegalPathCharactersWithString:@"_"], [title stringByReplacingIllegalPathCharactersWithString:@"_"], nil];
	return [NSString pathWithComponents:pathComponents];	
}

- (NSString *) customPathnameForCompactDisc:(CompactDisc *)disc
{
	NSParameterAssert(nil != disc);
	
	NSString *outputNamingFormat = [[NSUserDefaults standardUserDefaults] stringForKey:@"customOutputFileNamingFormat"];
	NSString *pathFormat = [outputNamingFormat stringByDeletingLastPathComponent];

	// Error checking
	NSRange illegalSpecifierRange = [pathFormat rangeOfString:@"{track"];
	if(NSNotFound != illegalSpecifierRange.location && 0 != illegalSpecifierRange.length)
		[[Logger sharedLogger] logMessageWithLevel:eLogMessageLevelDebug format:@"Custom file output format contains track specifiers: %@", pathFormat];

	NSArray *pathComponents = [pathFormat pathComponents];
	NSMutableArray *replacedComponents = [NSMutableArray array];

	// Replace the relevant format specifiers in each component separately
	AlbumMetadata *albumMetadata = disc.metadata;
	for(NSString *component in pathComponents) {
		NSMutableString *partialPath = [component mutableCopy];
		
		NSString *albumTitle = albumMetadata.title ? albumMetadata.title : @"";
		[partialPath replaceOccurrencesOfString:@"{albumTitle}" withString:albumTitle options:0 range:NSMakeRange(0, [partialPath length])];
		
		NSString *albumArtist = albumMetadata.artist ? albumMetadata.artist : @"";
		[partialPath replaceOccurrencesOfString:@"{albumArtist}" withString:albumArtist options:0 range:NSMakeRange(0, [partialPath length])];
		
		NSString *albumDate = albumMetadata.date ? albumMetadata.date : @"";
		[partialPath replaceOccurrencesOfString:@"{albumDate}" withString:albumDate options:0 range:NSMakeRange(0, [partialPath length])];
		
		NSString *discNumber = albumMetadata.discNumber ? [NSString stringWithFormat:@"%02lu", [albumMetadata.discNumber unsignedIntegerValue]] : @"";
		[partialPath replaceOccurrencesOfString:@"{discNumber}" withString:discNumber options:0 range:NSMakeRange(0, [partialPath length])];
		
		NSString *discTotal = albumMetadata.discTotal ? [NSString stringWithFormat:@"%02lu", [albumMetadata.discTotal unsignedIntegerValue]] : @"";
		[partialPath replaceOccurrencesOfString:@"{discTotal}" withString:discTotal options:0 range:NSMakeRange(0, [partialPath length])];
		
		[partialPath replaceIllegalPathCharactersWithString:@"_"];
		
		[replacedComponents addObject:partialPath];
	}
	
	return [NSString pathWithComponents:replacedComponents];
}

@end
