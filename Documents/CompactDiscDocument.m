/*
 *  Copyright (C) 2007 Stephen F. Booth <me@sbooth.org>
 *  All Rights Reserved
 */

#import "CompactDiscDocument.h"

#import "CompactDisc.h"
#import "SessionDescriptor.h"
#import "TrackDescriptor.h"
#import "AccurateRipDisc.h"
#import "AccurateRipTrack.h"
#import "DriveInformation.h"
#import "SectorRange.h"
#import "ExtractionOperation.h"
#import "ExternalCodecEncodeOperation.h"
#import "PreGapDetectionOperation.h"
#import "BitArray.h"
#include "AccurateRipUtilities.h"
#include "ExtractionConfigurationSheetController.h"

// ========================================
// KVC key names for the metadata dictionaries
// ========================================
NSString * const	kMetadataTitleKey						= @"title";
NSString * const	kMetadataAlbumTitleKey					= @"albumTitle";
NSString * const	kMetadataArtistKey						= @"artist";
NSString * const	kMetadataAlbumArtistKey					= @"albumArtist";
NSString * const	kMetadataGenreKey						= @"genre";
NSString * const	kMetadataComposerKey					= @"composer";
NSString * const	kMetadataDateKey						= @"date";
NSString * const	kMetadataCompilationKey					= @"compilation";
NSString * const	kMetadataTrackNumberKey					= @"trackNumber";
NSString * const	kMetadataTrackTotalKey					= @"trackTotal";
NSString * const	kMetadataDiscNumberKey					= @"discNumber";
NSString * const	kMetadataDiscTotalKey					= @"discTotal";
NSString * const	kMetadataCommentKey						= @"comment";
NSString * const	kMetadataISRCKey						= @"isrc";
NSString * const	kMetadataMCNKey							= @"mcn";
NSString * const	kMetadataBPMKey							= @"bpm";
NSString * const	kMetadataMusicDNSPUIDKey				= @"musicDNSPUID";
NSString * const	kMetadataMusicBrainzIDKey				= @"musicBrainzID";

// ========================================
// Context objects for observeValueForKeyPath:ofObject:change:context:
// ========================================
NSString * const	kKVOExtractionContext					= @"org.sbooth.Rip.CompactDiscDocument.ExtractionContext";

@interface CompactDiscDocument ()
@property (assign) CompactDisc * compactDisc;
@property (assign) AccurateRipDisc * accurateRipDisc;
@property (assign) DriveInformation * driveInformation;
@end

@interface CompactDiscDocument (Private)
- (void) extractionOperationStarted:(ExtractionOperation *)operation;
- (void) extractionOperationStopped:(ExtractionOperation *)operation;
- (void) preGapDetectionOperationStarted:(PreGapDetectionOperation *)operation;
- (void) preGapDetectionOperationStopped:(PreGapDetectionOperation *)operation;
- (void) diskWasEjected;
@end

// ========================================
// DiskArbitration eject callback
// ========================================
void ejectCallback(DADiskRef disk, DADissenterRef dissenter, void *context);
void ejectCallback(DADiskRef disk, DADissenterRef dissenter, void *context)
{
	
#pragma unused(disk)
	
	NSCParameterAssert(NULL != context);
	
	CompactDiscDocument *document = (CompactDiscDocument *)context;

	// If there is a dissenter, the ejection did not succeed
	if(dissenter)
		[document presentError:[NSError errorWithDomain:NSMachErrorDomain code:DADissenterGetStatus(dissenter) userInfo:nil]];
	// The disk was successfully ejected
	else
		[document diskWasEjected];
}

@implementation CompactDiscDocument

@synthesize trackController = _trackController;
@synthesize driveInformationController = _driveInformationController;
@synthesize compactDiscOperationQueue = _compactDiscOperationQueue;
@synthesize encodingQueue = _encodingQueue;

@synthesize disk = _disk;
@synthesize compactDisc = _compactDisc;
@synthesize accurateRipDisc = _accurateRipDisc;
@synthesize driveInformation = _driveInformation;
@synthesize metadata = _metadata;
@synthesize tracks = _tracks;

- (id) init
{
	if((self = [super init])) {
		_tracks = [[NSMutableArray alloc] init];
		_metadata = [[NSMutableDictionary alloc] init];
		_compactDiscOperationQueue = [[NSOperationQueue alloc] init];
		_encodingQueue = [[NSOperationQueue alloc] init];

		// Only allow one compact disc operation at a time
		[self.compactDiscOperationQueue setMaxConcurrentOperationCount:1];
		
		// Observe changes in the compact disc operations array, to be notified when each operation starts and stops
		[self.compactDiscOperationQueue addObserver:self forKeyPath:@"operations" options:(NSKeyValueObservingOptionOld |  NSKeyValueObservingOptionNew) context:kKVOExtractionContext];
	}
	return self;
}

- (void) finalize
{
	if(_disk)
		CFRelease(_disk), _disk = NULL;
	
	[super finalize];
}

- (void) awakeFromNib
{
	// Set the default sort descriptors for the track table
	NSSortDescriptor *trackNumberSortDescriptor = [[NSSortDescriptor alloc] initWithKey:@"number" ascending:YES];
	[self.trackController setSortDescriptors:[NSArray arrayWithObject:trackNumberSortDescriptor]];
}

- (BOOL) validateMenuItem:(NSMenuItem *)menuItem
{
	if([menuItem action] == @selector(copySelectedTracks:)) {
		NSPredicate *selectedTracksPredicate = [NSPredicate predicateWithFormat:@"selected == 1"];
		NSArray *selectedTracks = [self.tracks filteredArrayUsingPredicate:selectedTracksPredicate];
		return (0 != selectedTracks.count);
	}
	else if([menuItem action] == @selector(copyImage:))
		return YES;
	else if([menuItem action] == @selector(detectPreGaps:)) {
		NSPredicate *selectedTracksPredicate = [NSPredicate predicateWithFormat:@"selected == 1"];
		NSArray *selectedTracks = [self.tracks filteredArrayUsingPredicate:selectedTracksPredicate];
		return (0 != selectedTracks.count);
	}
	else
		return [super validateMenuItem:menuItem];
}

- (BOOL) validateToolbarItem:(NSToolbarItem *)toolbarItem
{
	if([toolbarItem action] == @selector(copySelectedTracks:)) {
		NSPredicate *selectedTracksPredicate = [NSPredicate predicateWithFormat:@"selected == 1"];
		NSArray *selectedTracks = [self.tracks filteredArrayUsingPredicate:selectedTracksPredicate];
		return (0 != selectedTracks.count);
	}
	else if([toolbarItem action] == @selector(copyImage:))
		return YES;
	else if([toolbarItem action] == @selector(detectPreGaps:)) {
		NSPredicate *selectedTracksPredicate = [NSPredicate predicateWithFormat:@"selected == 1"];
		NSArray *selectedTracks = [self.tracks filteredArrayUsingPredicate:selectedTracksPredicate];
		return (0 != selectedTracks.count);
	}
	else
		return [super validateToolbarItem:toolbarItem];
}

- (void) observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context
{
	if(kKVOExtractionContext == context) {
		NSInteger changeKind = [[change objectForKey:NSKeyValueChangeKindKey] integerValue];
		
		if(NSKeyValueChangeInsertion == changeKind) {
			for(NSOperation *operation in [change objectForKey:NSKeyValueChangeNewKey]) {
				if([operation isKindOfClass:[ExtractionOperation class]])
					[self extractionOperationStarted:(ExtractionOperation *)operation];
				else if([operation isKindOfClass:[PreGapDetectionOperation class]])
					[self preGapDetectionOperationStarted:(PreGapDetectionOperation *)operation];
			}
		}
		else if(NSKeyValueChangeRemoval == changeKind) {
			for(NSOperation *operation in [change objectForKey:NSKeyValueChangeOldKey])
				if([operation isKindOfClass:[ExtractionOperation class]])
					[self extractionOperationStopped:(ExtractionOperation *)operation];
				else if([operation isKindOfClass:[PreGapDetectionOperation class]])
					[self preGapDetectionOperationStopped:(PreGapDetectionOperation *)operation];
		}
	}
	else
		[super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
}

#pragma mark Core Data

// All instances of this class share the application's ManagedObjectContext and ManagedObjectModel
- (NSManagedObjectContext *) managedObjectContext
{
	return [[[NSApplication sharedApplication] delegate] managedObjectContext];
}

- (id) managedObjectModel
{
	return [[[NSApplication sharedApplication] delegate] managedObjectModel];
}

- (void) setDisk:(DADiskRef)disk
{
	if(disk != _disk) {
		if(_disk)
			CFRelease(_disk), _disk = NULL;
		
		self.compactDisc = nil;
		self.accurateRipDisc = nil;
		self.driveInformation = nil;
		
		if(disk) {
			_disk = DADiskCopyWholeDisk(disk);
			self.compactDisc = [[CompactDisc alloc] initWithDADiskRef:self.disk];
			self.accurateRipDisc = [[AccurateRipDisc alloc] initWithCompactDisc:self.compactDisc];
			self.driveInformation = [[DriveInformation alloc] initWithDADiskRef:self.disk];

			if(!self.driveInformation.readOffset)
				NSLog(@"Read offset is not configured for drive %@", self.driveInformation.deviceIdentifier);
			
			self.driveInformation.readOffset = [NSNumber numberWithInt:102];
			
			[self.accurateRipDisc performAccurateRipQuery:self];
		}
	}
}

- (void) setCompactDisc:(CompactDisc *)compactDisc
{
	if(compactDisc != _compactDisc) {
		_compactDisc = [compactDisc copy];
		
		// For multi-session discs only the first session is used
		SessionDescriptor *session = [self.compactDisc sessionNumber:1];
		
		[self willChangeValueForKey:@"tracks"];
		_tracks = [[NSMutableArray alloc] init];
		
		NSUInteger trackNumber;
		for(trackNumber = session.firstTrack; trackNumber <= session.lastTrack; ++trackNumber) {
			TrackDescriptor *track = [self.compactDisc trackNumber:trackNumber];
			NSMutableDictionary *trackDictionary = [[NSMutableDictionary alloc] init];

			[trackDictionary setObject:[[NSMutableDictionary alloc] init] forKey:@"metadata"];

			[trackDictionary setObject:[NSNumber numberWithBool:NO] forKey:@"selected"];
			[trackDictionary setObject:[NSNumber numberWithInteger:track.number] forKey:@"number"];
			[trackDictionary setObject:[NSNumber numberWithInteger:track.channels] forKey:@"channels"];
			[trackDictionary setObject:[NSNumber numberWithBool:track.preEmphasis] forKey:@"preEmphasis"];
			[trackDictionary setObject:[NSNumber numberWithBool:track.copyPermitted] forKey:@"copyPermitted"];

			[trackDictionary setObject:[NSNumber numberWithInteger:[self.compactDisc firstSectorForTrack:trackNumber]] forKey:@"firstSector"];
			[trackDictionary setObject:[NSNumber numberWithInteger:[self.compactDisc lastSectorForTrack:trackNumber]] forKey:@"lastSector"];
			[trackDictionary setObject:[NSNumber numberWithInteger:([self.compactDisc lastSectorForTrack:trackNumber] - [self.compactDisc firstSectorForTrack:trackNumber] + 1)] forKey:@"sectorCount"];
			
			[_tracks addObject:trackDictionary];
		}
		
		[self didChangeValueForKey:@"tracks"];
	}
}

- (NSString *) windowNibName
{
	return @"CompactDiscDocument";
}

- (void) windowControllerDidLoadNib:(NSWindowController *)aController
{
	[super windowControllerDidLoadNib:aController];
}

/*- (NSData *) dataOfType:(NSString *)typeName error:(NSError **)outError
{
	
#pragma unused(typeName)
	
	if(NULL != outError)
		*outError = [NSError errorWithDomain:NSOSStatusErrorDomain code:unimpErr userInfo:NULL];

	return nil;
}

- (BOOL) readFromData:(NSData *)data ofType:(NSString *)typeName error:(NSError **)outError
{

#pragma unused(data)
#pragma unused(typeName)

	if(NULL != outError)
		*outError = [NSError errorWithDomain:NSOSStatusErrorDomain code:unimpErr userInfo:NULL];

	return YES;
}*/

- (void) tableView:(NSTableView *)aTableView willDisplayCell:(id)aCell forTableColumn:(NSTableColumn *)aTableColumn row:(NSInteger)rowIndex
{

#pragma unused(aTableView)

	if([[aTableColumn identifier] isEqualToString:@"selected"]) {
		[aCell setTitle:[[[[_trackController arrangedObjects] objectAtIndex:rowIndex] valueForKey:@"number"] stringValue]];
		
	}
}

#pragma mark Action Methods

// ========================================
// Copy the selected tracks to intermediate WAV files, then to the encoder
- (IBAction) copySelectedTracks:(id)sender
{
	
#pragma unused(sender)
	
	NSPredicate *selectedTracksPredicate = [NSPredicate predicateWithFormat:@"selected == 1"];
	NSArray *selectedTracks = [self.tracks filteredArrayUsingPredicate:selectedTracksPredicate];
	
	if(0 == selectedTracks.count) {
		NSBeep();
		return;
	}
	
	// Limit the audio extraction to the first session
	SessionDescriptor *session = [self.compactDisc sessionNumber:1];
	
	for(NSDictionary *trackDictionary in selectedTracks) {		
		SectorRange *trackSectorRange = [SectorRange sectorRangeWithFirstSector:[[trackDictionary objectForKey:@"firstSector"] integerValue]
																	 lastSector:[[trackDictionary objectForKey:@"lastSector"] integerValue]];

		ExtractionOperation *trackExtractionOperation = [[ExtractionOperation alloc] init];
		
		trackExtractionOperation.disk = self.disk;
		trackExtractionOperation.sectors = trackSectorRange;
		trackExtractionOperation.session = session;
		trackExtractionOperation.trackNumber = [trackDictionary objectForKey:@"number"];
		trackExtractionOperation.readOffset = self.driveInformation.readOffset;
		trackExtractionOperation.url = [NSURL fileURLWithPath:[NSString stringWithFormat:@"/tmp/Track %@.wav", [trackDictionary objectForKey:@"number"]]];
		
		[self.compactDiscOperationQueue addOperation:trackExtractionOperation];
	}
}

- (void) showStreamInformationSheetDidEnd:(NSWindow *)sheet returnCode:(int)returnCode contextInfo:(void *)contextInfo
{
	NSLog(@"showStreamInformationSheetDidEnd");

	[sheet orderOut:self];
}

- (IBAction) copyImage:(id)sender
{

#pragma unused(sender)

	ExtractionConfigurationSheetController *extractionConfigurationSheetController = [[ExtractionConfigurationSheetController alloc] init];
	
	[[NSApplication sharedApplication] beginSheet:[extractionConfigurationSheetController window] 
								   modalForWindow:[self windowForSheet] 
									modalDelegate:self 
								   didEndSelector:@selector(showStreamInformationSheetDidEnd:returnCode:contextInfo:) 
									  contextInfo:extractionConfigurationSheetController];

	/*
	SectorRange *imageSectorRange = [SectorRange sectorRangeWithFirstSector:[self.compactDisc firstSectorForSession:1]
																 lastSector:[self.compactDisc lastSectorForSession:1]];
	
	ExtractionOperation *imageExtractionOperation = [[ExtractionOperation alloc] init];
	
	imageExtractionOperation.disk = self.disk;
	imageExtractionOperation.sectors = imageSectorRange;
	imageExtractionOperation.session = [self.compactDisc sessionNumber:1];
	imageExtractionOperation.readOffset = self.driveInformation.readOffset;
	imageExtractionOperation.url = [NSURL fileURLWithPath:@"/tmp/Disc Image.wav"];
	
	[self.compactDiscOperationQueue addOperation:imageExtractionOperation];
	 */
}

- (IBAction) detectPreGaps:(id)sender
{

#pragma unused(sender)
	
	NSPredicate *selectedTracksPredicate = [NSPredicate predicateWithFormat:@"selected == 1"];
	NSArray *selectedTracks = [self.tracks filteredArrayUsingPredicate:selectedTracksPredicate];
	
	if(0 == selectedTracks.count) {
		NSBeep();
		return;
	}
	
	for(NSDictionary *trackDictionary in selectedTracks) {
		PreGapDetectionOperation *preGapDetectionOperation = [[PreGapDetectionOperation alloc] init];
		
		preGapDetectionOperation.disk = self.disk;
		preGapDetectionOperation.trackNumber = [trackDictionary objectForKey:@"number"];
		
		[self.compactDiscOperationQueue addOperation:preGapDetectionOperation];
	}
}

- (IBAction) ejectDisc:(id)sender
{

#pragma unused(sender)
	
	// Don't allow ejections if extraction is in progress
	if(self.compactDiscOperationQueue.operations.count) {
		NSBeep();
		return;
	}
	
	// Register the eject request
	DADiskEject(self.disk, kDADiskEjectOptionDefault, ejectCallback, self);
}

#pragma mark KVC Accessors for tracks

- (NSUInteger) countOfTracks
{
	return [_tracks count];
}

- (TrackDescriptor *) objectInTracksAtIndex:(NSUInteger)index
{
	return [_tracks objectAtIndex:index];
}

- (void) getTracks:(id *)buffer range:(NSRange)range
{
	[_tracks getObjects:buffer range:range];
}

@end

@implementation CompactDiscDocument (Private)

- (void) extractionOperationStarted:(ExtractionOperation *)operation
{
	NSParameterAssert(nil != operation);

	NSLog(@"Extraction to %@ started", operation.url.path);
}

- (void) extractionOperationStopped:(ExtractionOperation *)operation
{
	NSParameterAssert(nil != operation);
	
	// Delete the output file if the operation was cancelled or did not succeed
	if(operation.error || operation.isCancelled) {
		if(operation.error)
			[self presentError:operation.error];
			
		NSError *error = nil;
		if(![[NSFileManager defaultManager] removeItemAtPath:operation.url.path error:&error])
			[self presentError:error];
		return;
	}

	NSLog(@"Extraction to %@ finished, %u C2 errors.  MD5 = %@", operation.url.path, operation.errorFlags.countOfOnes, operation.md5);

	NSMutableDictionary *extractionResult = [NSMutableDictionary dictionary];
	
	[extractionResult setObject:operation.url forKey:@"url"];
	[extractionResult setObject:operation.errorFlags forKey:@"errorFlags"];
	[extractionResult setObject:operation.md5 forKey:@"md5"];
	
	// If this disc was found in Accurate Rip, verify the checksum
	if(self.accurateRipDisc.discFound) {
		
		// If the extraction was for a single track, determine the checksum for the entire extracted file
		if(operation.trackNumber) {
			NSUInteger accurateRipCRC = calculateAccurateRipCRCForFile(operation.url.path, 
																	   operation.session.firstTrack == operation.trackNumber.unsignedIntegerValue,
																	   operation.session.lastTrack == operation.trackNumber.unsignedIntegerValue);
			
			AccurateRipTrack *accurateRipTrack = [self.accurateRipDisc trackNumber:operation.trackNumber.unsignedIntegerValue];

			if(accurateRipTrack && accurateRipTrack.CRC == accurateRipCRC) {
				NSLog(@"Track accurately ripped, confidence %i", accurateRipTrack.confidenceLevel);
				[extractionResult setObject:[NSNumber numberWithUnsignedInteger:accurateRipTrack.confidenceLevel] forKey:@"confidenceLevel"];
				
				// Since the track was accurately ripped, ship it off to the encoder(s)
/*				ExternalCodecEncodeOperation *encodeOperation = [[ExternalCodecEncodeOperation alloc] init];
				
				NSMutableArray *arguments = [NSMutableArray array];
				
				[arguments addObject:operation.path];
				[arguments addObject:@"-o"];
				[arguments addObject:[[operation.path stringByDeletingPathExtension] stringByAppendingPathExtension:@"flac"]];

				encodeOperation.codecPath = @"/Users/me/Development/flac-1.2.1/src/flac/flac";
				encodeOperation.arguments = arguments;
				
				[self.encodingQueue addOperation:encodeOperation];*/
			}
		}
		// Otherwise, the extraction was to an image and each track must be verified as a region of the file
		else {
			BOOL allTracksWereAccuratelyExtracted = YES;
			
			for(NSDictionary *trackInformation in self.tracks) {
				NSUInteger trackNumber = [[trackInformation objectForKey:@"number"] unsignedIntegerValue];
				
				NSUInteger accurateRipCRC = calculateAccurateRipCRCForFileRegion(operation.url.path, 
																				 [[trackInformation objectForKey:@"firstSector"] unsignedIntegerValue],
																				 [[trackInformation objectForKey:@"lastSector"] unsignedIntegerValue],
																				 operation.session.firstTrack == trackNumber,
																				 operation.session.lastTrack == trackNumber);
				
				AccurateRipTrack *accurateRipTrack = [self.accurateRipDisc trackNumber:trackNumber];
				
				if(accurateRipTrack && accurateRipTrack.CRC == accurateRipCRC) {
					NSLog(@"Track %i accurately ripped, confidence %i", trackNumber, accurateRipTrack.confidenceLevel);
				}
				else
					allTracksWereAccuratelyExtracted = NO;
			}
			
			// If all tracks were accurately ripped, ship the image off to the encoder(s)
			if(allTracksWereAccuratelyExtracted) {
				
			}
		}
	}
	// Otherwise, re-rip the track if any C2 error flags were returned
	else if(operation.errorFlags.countOfOnes) {
		
	}
	
}

- (void) preGapDetectionOperationStarted:(PreGapDetectionOperation *)operation
{
	NSParameterAssert(nil != operation);
	
}

- (void) preGapDetectionOperationStopped:(PreGapDetectionOperation *)operation
{
	NSParameterAssert(nil != operation);

	if(operation.error || operation.isCancelled) {
		if(operation.error)
			[self presentError:operation.error];		
		return;
	}
	
	NSLog(@"Pre-gap for track %@: %@", operation.trackNumber, operation.preGap);
}

- (void) diskWasEjected
{
	
}

@end
