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

#import "FileUtilities.h"

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
// Create the output filename to use for the given ExtractionRecord
// ========================================
static NSString *
filenameForExtractionRecord(ExtractionRecord *extractionRecord)
{
	NSCParameterAssert(nil != extractionRecord);
	
	NSString *filename = nil;
	
	// Only a single track was extracted
	if(1 == extractionRecord.tracks.count) {
		TrackDescriptor *track = extractionRecord.firstTrack.track;

		NSString *title = track.metadata.title;
		if(nil == title)
			title = NSLocalizedString(@"Unknown Title", @"");
		
		// Build up the sanitized track name
		filename = [NSString stringWithFormat:@"%02lu %@", track.number.unsignedIntegerValue, makeStringSafeForFilename(title)];
	}
	else {
		CompactDisc *disc = extractionRecord.disc;
		
		NSString *title = disc.metadata.title;
		if(nil == title)
			title = NSLocalizedString(@"Unknown Album", @"");
		
		// Build up the sanitized file name
		if(extractionRecord.tracks.count != disc.firstSession.tracks.count) {
			ExtractedTrackRecord *firstTrack = extractionRecord.firstTrack;
			ExtractedTrackRecord *lastTrack = extractionRecord.lastTrack;
			
			filename = [NSString stringWithFormat:@"%@ (%@ - %@)", makeStringSafeForFilename(title), firstTrack.track.number, lastTrack.track.number];
		}
		else
			filename = makeStringSafeForFilename(title);
	}
	
	return filename;
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

	return [bundleAName compare:bundleBName];;
}

// ========================================
// KVC key names for the encoder dictionaries
// ========================================
NSString * const	kEncoderBundleKey						= @"bundle";
NSString * const	kEncoderSettingsKey						= @"settings";

// ========================================
// Static variables
// ========================================
static EncoderManager *sSharedEncoderManager				= nil;

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
	
	NSString *title = disc.metadata.title;
	if(nil == title)
		title = NSLocalizedString(@"Unknown Album", @"");
	
	NSString *artist = disc.metadata.artist;
	if(nil == artist)
		artist = NSLocalizedString(@"Unknown Artist", @"");
	
	// Build up the sanitized Artist/Album structure
	NSArray *pathComponents = [NSArray arrayWithObjects:makeStringSafeForFilename(artist), makeStringSafeForFilename(title), nil];
	NSString *path = [NSString pathWithComponents:pathComponents];
	
	// Append it to the output folder
	NSURL *outputFolderURL = [NSUnarchiver unarchiveObjectWithData:[[NSUserDefaults standardUserDefaults] dataForKey:@"outputDirectory"]];
	NSString *outputPath = [[outputFolderURL path] stringByAppendingPathComponent:path];
	
	return [NSURL fileURLWithPath:outputPath];
}

- (BOOL) encodeURL:(NSURL *)inputURL extractionRecord:(ExtractionRecord *)extractionRecord error:(NSError **)error
{
	NSParameterAssert(nil != inputURL);
	NSParameterAssert(nil != extractionRecord);
	
	NSString *defaultEncoder = [[NSUserDefaults standardUserDefaults] stringForKey:@"defaultEncoder"];
	
	PlugInManager *plugInManager = [PlugInManager sharedPlugInManager];
	NSBundle *encoderBundle = [plugInManager plugInForIdentifier:defaultEncoder];
	
	if(![encoderBundle loadAndReturnError:error])
		return NO;
	
	NSDictionary *encoderSettings = [[NSUserDefaults standardUserDefaults] dictionaryForKey:defaultEncoder];
	
	Class encoderClass = [encoderBundle principalClass];
	NSObject <EncoderInterface> *encoderInterface = [[encoderClass alloc] init];
	
	// Build the filename for the output from the disc's folder, the track's name and number,
	// and the encoder's output path extension
	NSURL *baseURL = [self outputURLForCompactDisc:extractionRecord.disc];
	NSString *filename = filenameForExtractionRecord(extractionRecord);
	NSString *pathExtension = [encoderInterface pathExtensionForSettings:encoderSettings];
	NSString *pathname = [filename stringByAppendingPathExtension:pathExtension];
	NSString *outputPath = [[baseURL path] stringByAppendingPathComponent:pathname];
	
	// Ensure the output folder exists
	if(![[NSFileManager defaultManager] createDirectoryAtPath:[baseURL path] withIntermediateDirectories:YES attributes:nil error:error]) {
		return NO;
	}
	
	EncodingOperation *encodingOperation = [encoderInterface encodingOperation];
	
	encodingOperation.inputURL = inputURL;
	encodingOperation.outputURL = [NSURL fileURLWithPath:outputPath];
	encodingOperation.settings = encoderSettings;
	encodingOperation.metadata = metadataForExtractionRecord(extractionRecord);
	
#if DEBUG
	NSLog(@"Encoding %@ to %@ using %@", [encodingOperation.inputURL path], [encodingOperation.outputURL path], [encoderBundle objectForInfoDictionaryKey:@"EncoderName"]);
#endif

	[self.queue addOperation:encodingOperation];
	
	// Communicate the output URL back to the caller
	extractionRecord.URL = encodingOperation.outputURL;
	
	return YES;
}

@end
