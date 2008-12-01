/*
 *  Copyright (C) 2008 Stephen F. Booth <me@sbooth.org>
 *  All Rights Reserved
 */

#import "EncoderManager.h"
#import "PlugInManager.h"
#import "EncoderInterface/EncoderInterface.h"
#import "EncoderInterface/EncodingOperation.h"
#import "EncoderInterface/EncodingPostProcessingOperation.h"

#import "CompactDisc.h"
#import "CompactDisc+CueSheetGeneration.h"
#import "SessionDescriptor.h"
#import "TrackDescriptor.h"

#import "AlbumMetadata.h"
#import "TrackMetadata.h"

#import "TrackExtractionRecord.h"
#import "ImageExtractionRecord.h"

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
filenameForTrackExtractionRecord(TrackExtractionRecord *trackExtractionRecord)
{
	NSCParameterAssert(nil != trackExtractionRecord);
		
	// Only a single track was extracted
	TrackDescriptor *track = trackExtractionRecord.track;

	NSString *title = track.metadata.title;
	if(nil == title)
		title = NSLocalizedString(@"Unknown Title", @"");
	
	// Build up the sanitized track name
	return [NSString stringWithFormat:@"%02lu %@", track.number.unsignedIntegerValue, makeStringSafeForFilename(title)];
}

static NSString *
filenameForImageExtractionRecord(ImageExtractionRecord *imageExtractionRecord)
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
		
		filename = [NSString stringWithFormat:@"%@ (%@ - %@)", makeStringSafeForFilename(title), firstTrack.track.number, lastTrack.track.number];
	}
	else
		filename = makeStringSafeForFilename(title);

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

	return [bundleAName compare:bundleBName];
}

// ========================================
// Context objects for observeValueForKeyPath:ofObject:change:context:
// ========================================
static NSString * const kEncodingOperationKVOContext		= @"org.sbooth.Rip.EncoderManager.EncodingOperationKVOContext";
static NSString * const kEncodingPostProcessingOperationKVOContext		= @"org.sbooth.Rip.EncoderManager.EncodingPostProcessingOperationKVOContext";

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
			if(![[NSFileManager defaultManager] removeItemAtPath:[operation.inputURL path] error:&error])
				[[NSApplication sharedApplication] presentError:error];
		}
	}
	else if(kEncodingPostProcessingOperationKVOContext == context) {
		EncodingPostProcessingOperation *operation = (EncodingPostProcessingOperation *)object;

		if([keyPath isEqualToString:@"isCancelled"] || [keyPath isEqualToString:@"isFinished"]) {
			[operation removeObserver:self forKeyPath:@"isCancelled"];
			[operation removeObserver:self forKeyPath:@"isFinished"];

			if(operation.isImage) {
				// Remove the temporary cue sheet
				NSError *error = nil;
				if(![[NSFileManager defaultManager] removeItemAtPath:[operation.cueSheetURL path] error:&error])
					[[NSApplication sharedApplication] presentError:error];
			}
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

- (BOOL) encodeTrackExtractionRecord:(TrackExtractionRecord *)trackExtractionRecord error:(NSError **)error
{
	return [self encodeTrackExtractionRecord:trackExtractionRecord encodingOperation:NULL delayPostProcessing:NO error:error];
}

- (BOOL) encodeTrackExtractionRecord:(TrackExtractionRecord *)trackExtractionRecord encodingOperation:(EncodingOperation **)encodingOperation delayPostProcessing:(BOOL)delayPostProcessing error:(NSError **)error
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
	
	operation.inputURL = trackExtractionRecord.inputURL;
	operation.outputURL = outputURL;
	operation.settings = encoderSettings;
	operation.metadata = metadataForTrackExtractionRecord(trackExtractionRecord);
	
	// Observe the operation's progress so the input file can be deleted when it completes
	[operation addObserver:self forKeyPath:@"isCancelled" options:NSKeyValueObservingOptionNew context:kEncodingOperationKVOContext];
	[operation addObserver:self forKeyPath:@"isFinished" options:NSKeyValueObservingOptionNew context:kEncodingOperationKVOContext];

	[[Logger sharedLogger] logMessageWithLevel:eLogMessageLevelDebug format:@"Encoding %@ to %@ using %@", [operation.inputURL path], [operation.outputURL path], [encoderBundle objectForInfoDictionaryKey:@"EncoderName"]];

	if(!delayPostProcessing)
		[self postProcessEncodingOperation:operation forTrackExtractionRecord:trackExtractionRecord error:error];
	
	[self.queue addOperation:operation];
	
	// Communicate the output URL back to the caller
	trackExtractionRecord.outputURL = operation.outputURL;
	
	if(encodingOperation)
		*encodingOperation = operation;
	
	return YES;
}

- (BOOL) encodeImageExtractionRecord:(ImageExtractionRecord *)imageExtractionRecord error:(NSError **)error
{
	return [self encodeImageExtractionRecord:imageExtractionRecord encodingOperation:NULL delayPostProcessing:NO error:error];
}

- (BOOL) encodeImageExtractionRecord:(ImageExtractionRecord *)imageExtractionRecord encodingOperation:(EncodingOperation **)encodingOperation delayPostProcessing:(BOOL)delayPostProcessing error:(NSError **)error
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
	
	operation.inputURL = imageExtractionRecord.inputURL;
	operation.outputURL = outputURL;
	operation.settings = encoderSettings;
	operation.metadata = metadataForImageExtractionRecord(imageExtractionRecord);
	
	// Observe the operation's progress so the input file can be deleted when it completes
	[operation addObserver:self forKeyPath:@"isCancelled" options:NSKeyValueObservingOptionNew context:kEncodingOperationKVOContext];
	[operation addObserver:self forKeyPath:@"isFinished" options:NSKeyValueObservingOptionNew context:kEncodingOperationKVOContext];
	
	[[Logger sharedLogger] logMessageWithLevel:eLogMessageLevelDebug format:@"Encoding %@ to %@ using %@", [operation.inputURL path], [operation.outputURL path], [encoderBundle objectForInfoDictionaryKey:@"EncoderName"]];
	
	if(!delayPostProcessing)
		[self postProcessEncodingOperation:operation forImageExtractionRecord:imageExtractionRecord error:error];
	
	[self.queue addOperation:operation];
		
	// Communicate the output URL back to the caller
	imageExtractionRecord.outputURL = operation.outputURL;
	
	if(encodingOperation)
		*encodingOperation = operation;
	
	return YES;
}

// ========================================
// Post-encoding processing
- (BOOL) postProcessEncodingOperation:(EncodingOperation *)encodingOperation forTrackExtractionRecord:(TrackExtractionRecord *)trackExtractionRecord error:(NSError **)error
{
	return [self postProcessEncodingOperations:[NSArray arrayWithObject:encodingOperation] forTrackExtractionRecords:[NSArray arrayWithObject:trackExtractionRecord] error:error];
}

- (BOOL) postProcessEncodingOperations:(NSArray *)encodingOperations forTrackExtractionRecords:(NSArray *)trackExtractionRecords error:(NSError **)error
{
	NSParameterAssert(nil != encodingOperations);
	NSParameterAssert(nil != trackExtractionRecords);
	NSParameterAssert([encodingOperations count] == [trackExtractionRecords count]);
	
	EncodingOperation *baseOperation = [encodingOperations lastObject];
	
	NSBundle *encoderBundle = [NSBundle bundleForClass:[baseOperation class]];
	
	if(![encoderBundle loadAndReturnError:error])
		return NO;
	
	Class encoderClass = [encoderBundle principalClass];
	NSObject <EncoderInterface> *encoderInterface = [[encoderClass alloc] init];

	EncodingPostProcessingOperation *operation = [encoderInterface encodingPostProcessingOperation];

	operation.isImage = NO;
	operation.trackURLs = [encodingOperations valueForKey:@"outputURL"];
	operation.trackMetadata = [baseOperation valueForKey:@"metadata"];
	operation.settings = [baseOperation settings];
	
	// Observe the operation's progress
	[operation addObserver:self forKeyPath:@"isCancelled" options:NSKeyValueObservingOptionNew context:kEncodingPostProcessingOperationKVOContext];
	[operation addObserver:self forKeyPath:@"isFinished" options:NSKeyValueObservingOptionNew context:kEncodingPostProcessingOperationKVOContext];
	
	// Add the encoding operations as dependencies for the post-processing
	for(NSOperation *encodingOperation in encodingOperations)
		[operation addDependency:encodingOperation];
	
	[self.queue addOperation:operation];

	return YES;
}

- (BOOL) postProcessEncodingOperation:(EncodingOperation *)encodingOperation forImageExtractionRecord:(ImageExtractionRecord *)imageExtractionRecord error:(NSError **)error
{
	NSParameterAssert(nil != encodingOperation);
	NSParameterAssert(nil != imageExtractionRecord);

	NSBundle *encoderBundle = [NSBundle bundleForClass:[encodingOperation class]];
	
	if(![encoderBundle loadAndReturnError:error])
		return NO;
	
	Class encoderClass = [encoderBundle principalClass];
	NSObject <EncoderInterface> *encoderInterface = [[encoderClass alloc] init];
	
	// Create a temporary cue sheet
	NSURL *cueSheetURL = temporaryURLWithExtension(@"cue");
	if(![imageExtractionRecord.disc writeCueSheetToURL:cueSheetURL error:error])
		return NO;
	
	EncodingPostProcessingOperation *operation = [encoderInterface encodingPostProcessingOperation];
	
	operation.isImage = YES;
	operation.imageURL = encodingOperation.outputURL;
	operation.imageMetadata = encodingOperation.metadata;
	operation.cueSheetURL = cueSheetURL;
	operation.settings = encodingOperation.settings;
	
	// Observe the operation's progress
	[operation addObserver:self forKeyPath:@"isCancelled" options:NSKeyValueObservingOptionNew context:kEncodingPostProcessingOperationKVOContext];
	[operation addObserver:self forKeyPath:@"isFinished" options:NSKeyValueObservingOptionNew context:kEncodingPostProcessingOperationKVOContext];
	
	// Add the encoding operations as dependencies for the post-processing
	[operation addDependency:encodingOperation];
	
	[self.queue addOperation:operation];
	
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

@end
