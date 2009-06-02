/*
 *  Copyright (C) 2007 - 2009 Stephen F. Booth <me@sbooth.org>
 *  All Rights Reserved
 */

#import "CompactDiscWindowController.h"
#import "CompactDiscWindowController+LogFileGeneration.h"

#import "CompactDisc.h"
#import "CompactDisc+CueSheetGeneration.h"
#import "SessionDescriptor.h"
#import "TrackDescriptor.h"
#import "AlbumMetadata.h"
#import "AlbumArtwork.h"
#import "TrackMetadata.h"

#import "MetadataViewController.h"
#import "ExtractionViewController.h"

#import "AccurateRipQueryOperation.h"

#import "DriveInformation.h"

#import "MusicDatabaseInterface/MusicDatabaseInterface.h"
#import "MusicDatabaseInterface/MusicDatabaseQueryOperation.h"
#import "MusicDatabaseInterface/MusicDatabaseSubmissionOperation.h"
#import "MusicDatabaseMatchesSheetController.h"

#import "MetadataSourceInterface/MetadataSourceInterface.h"
#import "MetadataSourceInterface/MetadataSourceData.h"

#import "ReadOffsetCalculatorSheetController.h"
#import "ReadMCNSheetController.h"
#import "ReadISRCsSheetController.h"
#import "DetectPregapsSheetController.h"

#import "EncoderManager.h"
#import "MusicDatabaseManager.h"
#import "MetadataSourceManager.h"

#import "FileUtilities.h"
#import "AccurateRipDiscRecord.h"
#import "AccurateRipTrackRecord.h"

#import "NSString+PathSanitizationMethods.h"
#import "NSImage+BitmapRepresentationMethods.h"

#define WINDOW_BORDER_THICKNESS ((CGFloat)20)

// ========================================
// Extract the metadata from a disc into a dictionary
// ========================================
static NSDictionary * metadataForTrack(TrackDescriptor *track)
{
	NSCParameterAssert(nil != track);
	
	TrackMetadata *trackMetadata = track.metadata;
	NSMutableDictionary *metadata = [NSMutableDictionary dictionary];
	
	// Track number
	[metadata setObject:track.number forKey:kMetadataTrackNumberKey];
	
	// Track metadata
	if(trackMetadata.additionalMetadata)
		[metadata setObject:trackMetadata.additionalMetadata forKey:kMetadataAdditionalMetadataKey];
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
	if(trackMetadata.lyrics)
		[metadata setObject:trackMetadata.lyrics forKey:kMetadataLyricsKey];
	if(trackMetadata.musicBrainzID)
		[metadata setObject:trackMetadata.artist forKey:kMetadataMusicBrainzIDKey];
	if(trackMetadata.title)
		[metadata setObject:trackMetadata.title forKey:kMetadataTitleKey];

	return [metadata copy];
}

static NSDictionary * metadataForCompactDisc(CompactDisc *disc)
{
	NSCParameterAssert(nil != disc);

	AlbumMetadata *albumMetadata = disc.metadata;
	NSMutableDictionary *metadata = [NSMutableDictionary dictionary];
	
	// Track total
	[metadata setObject:[NSNumber numberWithUnsignedInteger:disc.firstSession.tracks.count] forKey:kMetadataTrackTotalKey];
	
	// Album metadata
	if(albumMetadata.additionalMetadata)
		[metadata setObject:albumMetadata.additionalMetadata forKey:kMetadataAdditionalMetadataKey];
	if(albumMetadata.artist)
		[metadata setObject:albumMetadata.artist forKey:kMetadataArtistKey];
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
		[metadata setObject:albumMetadata.musicBrainzID forKey:kMetadataMusicBrainzIDKey];
	if(albumMetadata.title)
		[metadata setObject:albumMetadata.title forKey:kMetadataTitleKey];
	
	// Album artwork
	NSImage *frontCoverImage = albumMetadata.artwork.frontCoverImage;
	if(frontCoverImage)
		[metadata setObject:frontCoverImage forKey:kAlbumArtFrontCoverKey];
	
	// Individual track metadata
	NSMutableArray *trackMetadataArray = [NSMutableArray array];
	for(TrackDescriptor *track in disc.firstSession.tracks)
		[trackMetadataArray addObject:metadataForTrack(track)];
	
	[metadata setObject:trackMetadataArray forKey:kTrackMetadataArrayKey];
	
	return [metadata copy];
}

// ========================================
// Context objects for observeValueForKeyPath:ofObject:change:context:
// ========================================
static NSString * const kOperationQueueKVOContext		= @"org.sbooth.Rip.CompactDiscWindowController.KVOContext";
static NSString * const kAccurateRipQueryKVOContext		= @"org.sbooth.Rip.CompactDiscWindowController.AccurateRipQueryKVOContext";
static NSString * const kMusicDatabaseQueryKVOContext	= @"org.sbooth.Rip.CompactDiscWindowController.MusicDatabaseQueryKVOContext";

@interface CompactDiscWindowController ()
@property (assign) CompactDisc * compactDisc;
@property (assign) DriveInformation * driveInformation;

@property (assign) MetadataViewController * metadataViewController;
@property (assign) ExtractionViewController * extractionViewController;

@property (readonly) NSOperationQueue * operationQueue;

@property (readonly) NSManagedObjectContext * managedObjectContext;
@property (readonly) id managedObjectModel;
@end

@interface CompactDiscWindowController (SheetCallbacks)
- (void) showMusicDatabaseMatchesSheetDidEnd:(NSWindow *)sheet returnCode:(int)returnCode contextInfo:(void *)contextInfo;
- (void) createCueSheetSavePanelDidEnd:(NSSavePanel *)sheet returnCode:(int)returnCode  contextInfo:(void *)contextInfo;
- (void) showSuccessfulExtractionSheetDidEnd:(NSWindow *)sheet returnCode:(int)returnCode contextInfo:(void *)contextInfo;
@end

@interface CompactDiscWindowController (ExtractionViewControllerMethods)
- (void) extractionFinishedWithReturnCode:(int)returnCode;
@end

@interface CompactDiscWindowController (Private)
- (void) diskWasEjected;
- (void) updateMetadataWithMusicDatabaseEntry:(id)musicDatabaseEntry;
- (void) toggleTableColumnVisible:(id)sender;
- (void) accurateRipQueryOperationDidReturn:(AccurateRipQueryOperation *)operation;
- (void) musicDatabaseQueryOperationDidReturn:(MusicDatabaseQueryOperation *)operation;
- (void) extractTracks:(NSSet *)tracks extractionMode:(eExtractionMode)extractionMode;
- (void) showSuccessfulExtractionSheetDismissalTimerFired:(NSTimer *)timer;
- (void) swapMainViewController:(NSViewController *)oldViewController withViewController:(NSViewController *)newViewController;
@end

// ========================================
// DiskArbitration callback functions
// ========================================
void unmountCallback(DADiskRef disk, DADissenterRef dissenter, void *context);
void ejectCallback(DADiskRef disk, DADissenterRef dissenter, void *context);

void unmountCallback(DADiskRef disk, DADissenterRef dissenter, void *context)
{
	NSCParameterAssert(NULL != context);
	
	CompactDiscWindowController *compactDiscWindowController = (CompactDiscWindowController *)context;

	// If there is a dissenter, the unmount did not succeed
	if(dissenter)
		[compactDiscWindowController presentError:[NSError errorWithDomain:NSMachErrorDomain code:DADissenterGetStatus(dissenter) userInfo:nil] 
								   modalForWindow:compactDiscWindowController.window 
										 delegate:nil 
							   didPresentSelector:NULL 
									  contextInfo:NULL];
	// The disk was successfully unmounted, so register the eject request
	else
		DADiskEject(disk, kDADiskEjectOptionDefault, ejectCallback, context);
}

void ejectCallback(DADiskRef disk, DADissenterRef dissenter, void *context)
{
	
#pragma unused(disk)
	
	NSCParameterAssert(NULL != context);
	
	CompactDiscWindowController *compactDiscWindowController = (CompactDiscWindowController *)context;

	// If there is a dissenter, the ejection did not succeed
	if(dissenter)
		[compactDiscWindowController presentError:[NSError errorWithDomain:NSMachErrorDomain code:DADissenterGetStatus(dissenter) userInfo:nil] 
								   modalForWindow:compactDiscWindowController.window 
										 delegate:nil 
							   didPresentSelector:NULL 
									  contextInfo:NULL];
	// The disk was successfully ejected
	else
		[compactDiscWindowController diskWasEjected];
}

@implementation CompactDiscWindowController

@synthesize operationQueue = _operationQueue;

@synthesize disk = _disk;
@synthesize compactDisc = _compactDisc;
@synthesize driveInformation = _driveInformation;

@synthesize metadataViewController = _metadataViewController;
@synthesize extractionViewController = _extractionViewController;

- (id) init
{
	if((self = [super initWithWindowNibName:@"CompactDiscWindow"])) {
		_operationQueue = [[NSOperationQueue alloc] init];

		// Register to receive NSManagedObjectContextDidSaveNotification to keep our MOC in sync
		[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(managedObjectContextDidSave:) name:NSManagedObjectContextDidSaveNotification object:nil];
	}
	
	return self;
}

- (void) finalize
{
	if(_disk)
		CFRelease(_disk), _disk = NULL;
	
	[super finalize];
}

- (void) windowDidLoad
{
	// Our window has a bottom border used to display the AccurateRip availability for this disc and total playing time
	[self.window setAutorecalculatesContentBorderThickness:YES forEdge:NSMinYEdge];
	[self.window setContentBorderThickness:WINDOW_BORDER_THICKNESS forEdge:NSMinYEdge];
	
	// Initially the main view in the window shows the disc's metadata
	_metadataViewController = [[MetadataViewController alloc] init];
	[_metadataViewController setRepresentedObject:self.compactDisc];
	
	_extractionViewController = [[ExtractionViewController alloc] init];

	[_mainView addSubview:[_metadataViewController view]];
	[self setNextResponder:_metadataViewController];
}

- (BOOL) validateMenuItem:(NSMenuItem *)menuItem
{
	// Only allow disc-related actions if the main metadata view is diplayed
	if(![[_metadataViewController view] isDescendantOf:_mainView])
		return NO;
	else if([menuItem action] == @selector(copySelectedTracks:)) {
		NSUInteger countOfSelectedTracks = self.compactDisc.firstSession.selectedTracks.count;
		
		if(1 == countOfSelectedTracks)
			[menuItem setTitle:NSLocalizedString(@"Copy Track", @"")];
		else
			[menuItem setTitle:NSLocalizedString(@"Copy Tracks", @"")];
		
		return (0 != countOfSelectedTracks);
	}
	else if([menuItem action] == @selector(detectPregaps:)) {
		NSUInteger countOfSelectedTracks = self.compactDisc.firstSession.selectedTracks.count;
		
		if(1 == countOfSelectedTracks)
			[menuItem setTitle:NSLocalizedString(@"Detect Pregap", @"")];
		else
			[menuItem setTitle:NSLocalizedString(@"Detect Pregaps", @"")];

		return (0 != countOfSelectedTracks);		
	}
	else if([menuItem action] == @selector(readISRCs:)) {
		NSUInteger countOfSelectedTracks = self.compactDisc.firstSession.selectedTracks.count;
		
		if(1 == countOfSelectedTracks)
			[menuItem setTitle:NSLocalizedString(@"Read ISRC", @"")];
		else
			[menuItem setTitle:NSLocalizedString(@"Read ISRCs", @"")];
			
		return (0 != countOfSelectedTracks);
	}
//	else if([menuItem action] == @selector(determineDriveReadOffset:)) {
//		if(self.driveInformation.productName)
//			[menuItem setTitle:[NSString stringWithFormat:NSLocalizedString(@"Determine Read Offset for \u201c%@ %@\u201d", @""), self.driveInformation.vendorName, self.driveInformation.productName]];
//		else
//			[menuItem setTitle:NSLocalizedString(@"Determine Read Offset", @"")];
//			
//		return YES;
//	}
	else if([menuItem action] == @selector(queryDefaultMusicDatabase:)) {
		NSBundle *defaultMusicDatabaseBundle = [[MusicDatabaseManager sharedMusicDatabaseManager] defaultMusicDatabase];
		id <MusicDatabaseInterface> musicDatabaseInterface = [[[defaultMusicDatabaseBundle principalClass] alloc] init];
		
		MusicDatabaseQueryOperation *queryOperation = [musicDatabaseInterface musicDatabaseQueryOperation];
//		if(queryOperation)
//			[menuItem setTitle:[NSString stringWithFormat:NSLocalizedString(@"Lookup Metadata Using %@", @""), [defaultMusicDatabaseBundle objectForInfoDictionaryKey:@"MusicDatabaseName"]]];

		return (nil != queryOperation);
	}
	else if([menuItem action] == @selector(submitToDefaultMusicDatabase:)) {
		NSBundle *defaultMusicDatabaseBundle = [[MusicDatabaseManager sharedMusicDatabaseManager] defaultMusicDatabase];
		id <MusicDatabaseInterface> musicDatabaseInterface = [[[defaultMusicDatabaseBundle principalClass] alloc] init];
		
		MusicDatabaseSubmissionOperation *submissionOperation = [musicDatabaseInterface musicDatabaseSubmissionOperation];
//		if(submissionOperation)
//			[menuItem setTitle:[NSString stringWithFormat:NSLocalizedString(@"Submit Metadata to %@ ", @""), [defaultMusicDatabaseBundle objectForInfoDictionaryKey:@"MusicDatabaseName"]]];
		
		return (nil != submissionOperation);
	}
	else if([self respondsToSelector:[menuItem action]])
		return YES;
	else
		return NO;
}

- (BOOL) validateToolbarItem:(NSToolbarItem *)theItem
{
	if(![[_metadataViewController view] isDescendantOf:_mainView])
		return NO;
	else if([theItem action] == @selector(copySelectedTracks:))
		return (0 != self.compactDisc.firstSession.selectedTracks.count);
	else if([theItem action] == @selector(detectPregaps:))
		return (0 != self.compactDisc.firstSession.selectedTracks.count);
	else if([self respondsToSelector:[theItem action]])
		return YES;
	else
		return NO;
}

- (void) observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context
{
	if(kAccurateRipQueryKVOContext == context) {
		AccurateRipQueryOperation *operation = (AccurateRipQueryOperation *)object;
		
		if([keyPath isEqualToString:@"isCancelled"] || [keyPath isEqualToString:@"isFinished"]) {
			[operation removeObserver:self forKeyPath:@"isExecuting"];
			[operation removeObserver:self forKeyPath:@"isCancelled"];
			[operation removeObserver:self forKeyPath:@"isFinished"];

			// KVO is thread-safe, but doesn't guarantee observeValueForKeyPath: will be called from the main thread
			if([NSThread isMainThread])
				[self accurateRipQueryOperationDidReturn:operation];
			else
				[self performSelectorOnMainThread:@selector(accurateRipQueryOperationDidReturn:) withObject:operation waitUntilDone:NO];
		}
	}
	else if(kMusicDatabaseQueryKVOContext == context) {
		MusicDatabaseQueryOperation *operation = (MusicDatabaseQueryOperation *)object;
		
		if([keyPath isEqualToString:@"isCancelled"] || [keyPath isEqualToString:@"isFinished"]) {
			[operation removeObserver:self forKeyPath:@"isExecuting"];
			[operation removeObserver:self forKeyPath:@"isCancelled"];
			[operation removeObserver:self forKeyPath:@"isFinished"];
			
			// KVO is thread-safe, but doesn't guarantee observeValueForKeyPath: will be called from the main thread
			if([NSThread isMainThread])
				[self musicDatabaseQueryOperationDidReturn:operation];
			else
				[self performSelectorOnMainThread:@selector(musicDatabaseQueryOperationDidReturn:) withObject:operation waitUntilDone:NO];
		}
	}
	else
		[super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
}

- (void) managedObjectContextDidSave:(NSNotification *)notification
{
	NSParameterAssert(nil != notification);

	// "Auto-refresh" objects changed in another MOC
	NSManagedObjectContext *managedObjectContext = [notification object];
	if(managedObjectContext != self.managedObjectContext)
		[self.managedObjectContext mergeChangesFromContextDidSaveNotification:notification];
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

#pragma mark NSWindow Delegate Methods

- (NSUndoManager *) windowWillReturnUndoManager:(NSWindow *)window
{

#pragma unused(window)
	
	return self.managedObjectContext.undoManager;
}

- (BOOL) windowShouldClose:(NSWindow *)window
{

#pragma unused(window)
	
	if(self.operationQueue.operations.count)
		return NO;
	else	
		return YES;
}

- (void) windowWillClose:(NSNotification *)notification
{
	
#pragma unused(notification)
	
	self.disk = NULL;
}

- (void) setDisk:(DADiskRef)disk
{
	if(disk != _disk) {
		if(_disk)
			CFRelease(_disk), _disk = NULL;
		
		self.compactDisc = nil;
		self.driveInformation = nil;
		
		[self.operationQueue cancelAllOperations];
		
		if(disk) {
			_disk = DADiskCopyWholeDisk(disk);
			self.compactDisc = [CompactDisc compactDiscWithDADiskRef:self.disk inManagedObjectContext:self.managedObjectContext];
			self.driveInformation = [DriveInformation driveInformationWithDADiskRef:self.disk inManagedObjectContext:self.managedObjectContext];

			// Set the window's represented URL to the disc's path
			CFDictionaryRef description = DADiskCopyDescription(_disk);
			
			CFURLRef volumePathURL = CFDictionaryGetValue(description, kDADiskDescriptionVolumePathKey);
			if(volumePathURL)
				[self.window setRepresentedURL:(NSURL *)volumePathURL];
			
			CFRelease(description);
			
			// Use the MusicBrainz disc ID as the window frame's autosave name
			[self.window setFrameAutosaveName:self.compactDisc.musicBrainzDiscID];
		}
		else
			[self.window setRepresentedURL:nil];
	}
}

#pragma mark MetadataSourceDelegate Methods

- (void) metadataSourceViewController:(NSViewController *)viewController finishedWithReturnCode:(int)returnCode
{
	// Replace the metadata source view with the metadata view
	[self swapMainViewController:viewController withViewController:_metadataViewController];
	
	if(NSCancelButton == returnCode)
		return;

	NSDictionary *metadataDictionary = [(MetadataSourceData *)[viewController representedObject] metadata];
	
	// Iterate over the metadata and save any changes that were made (to user-editable metadata only)
	
	// Album metadata
	AlbumMetadata *albumMetadata = self.compactDisc.metadata;

	NSDictionary *additionalMetadata = [metadataDictionary objectForKey:kMetadataAdditionalMetadataKey];
	if(additionalMetadata && ![albumMetadata.additionalMetadata isEqualToDictionary:additionalMetadata])
	   albumMetadata.additionalMetadata = additionalMetadata;
	
	NSString *artist = [metadataDictionary objectForKey:kMetadataArtistKey];
	if(artist && ![albumMetadata.artist isEqualToString:artist])
		albumMetadata.artist = artist;
	
	NSString *date = [metadataDictionary objectForKey:kMetadataReleaseDateKey];
	if(date && ![albumMetadata.date isEqualToString:date])
		albumMetadata.date = date;
	
	NSNumber *discNumber = [metadataDictionary objectForKey:kMetadataDiscNumberKey];
	if(discNumber && ![albumMetadata.discNumber isEqualToNumber:discNumber])
		albumMetadata.discNumber = discNumber;
	
	NSNumber *discTotal = [metadataDictionary objectForKey:kMetadataDiscTotalKey];
	if(discTotal && ![albumMetadata.discTotal isEqualToNumber:discTotal])
		albumMetadata.discTotal = discTotal;
	
	NSNumber *isCompilation = [metadataDictionary objectForKey:kMetadataCompilationKey];
	if(isCompilation && ![albumMetadata.isCompilation isEqualToNumber:isCompilation])
		albumMetadata.isCompilation = isCompilation;
	
	NSString *MCN = [metadataDictionary objectForKey:kMetadataMCNKey];
	if(MCN && ![albumMetadata.MCN isEqualToString:MCN])
		albumMetadata.MCN = MCN;
	
	NSString *musicBrainzID = [metadataDictionary objectForKey:kMetadataMusicBrainzIDKey];
	if(musicBrainzID && ![albumMetadata.musicBrainzID isEqualToString:musicBrainzID])
		albumMetadata.musicBrainzID = musicBrainzID;
	
	NSString *title = [metadataDictionary objectForKey:kMetadataTitleKey];
	if(title && ![albumMetadata.title isEqualToString:title])
		albumMetadata.title = title;
	
	// Album art
	NSImage *frontCoverImage = [metadataDictionary objectForKey:kAlbumArtFrontCoverKey];
	NSData *imageData = [frontCoverImage TIFFRepresentation];
	NSData *imageArchive = [NSArchiver archivedDataWithRootObject:imageData];
	if(imageArchive && ![albumMetadata.artwork.frontCover isEqual:imageArchive])
		albumMetadata.artwork.frontCover = imageArchive;
	
	// Track metadata
	NSArray *tracks = [metadataDictionary objectForKey:kTrackMetadataArrayKey];
	for(metadataDictionary in tracks) {
		NSNumber *trackNumber = [metadataDictionary objectForKey:kMetadataTrackNumberKey];
		TrackDescriptor *track = [self.compactDisc trackNumber:[trackNumber unsignedIntegerValue]];
		TrackMetadata *trackMetadata = track.metadata;
		
		if(!trackMetadata)
			continue;
		
		additionalMetadata = [metadataDictionary objectForKey:kMetadataAdditionalMetadataKey];
		if(additionalMetadata && ![trackMetadata.additionalMetadata isEqualToDictionary:additionalMetadata])
			trackMetadata.additionalMetadata = additionalMetadata;
		
		artist = [metadataDictionary objectForKey:kMetadataArtistKey];
		if(artist && ![trackMetadata.artist isEqualToString:artist])
			trackMetadata.artist = artist;

		NSString *composer = [metadataDictionary objectForKey:kMetadataComposerKey];
		if(composer && ![trackMetadata.composer isEqualToString:composer])
			trackMetadata.composer = composer;
		
		date = [metadataDictionary objectForKey:kMetadataReleaseDateKey];
		if(date && ![trackMetadata.date isEqualToString:date])
			trackMetadata.date = date;
		
		NSString *genre = [metadataDictionary objectForKey:kMetadataGenreKey];
		if(genre && ![trackMetadata.genre isEqualToString:genre])
			trackMetadata.genre = genre;
		
		NSString *ISRC = [metadataDictionary objectForKey:kMetadataISRCKey];
		if(ISRC && ![trackMetadata.ISRC isEqualToString:ISRC])
			trackMetadata.ISRC = ISRC;
		
		NSString *lyrics = [metadataDictionary objectForKey:kMetadataLyricsKey];
		if(lyrics && ![trackMetadata.lyrics isEqualToString:lyrics])
			trackMetadata.lyrics = lyrics;
		
		musicBrainzID = [metadataDictionary objectForKey:kMetadataMusicBrainzIDKey];
		if(musicBrainzID && ![trackMetadata.musicBrainzID isEqualToString:musicBrainzID])
			trackMetadata.musicBrainzID = musicBrainzID;
		
		title = [metadataDictionary objectForKey:kMetadataTitleKey];
		if(title && ![trackMetadata.title isEqualToString:title])
			trackMetadata.title = title;
	}
}

#pragma mark Action Methods

- (IBAction) selectAllTracks:(id)sender
{
	
#pragma unused(sender)

	[self.compactDisc.firstSession.tracks setValue:[NSNumber numberWithBool:YES] forKey:@"isSelected"];
	
}

- (IBAction) deselectAllTracks:(id)sender
{
	
#pragma unused(sender)
	
	[self.compactDisc.firstSession.tracks setValue:[NSNumber numberWithBool:NO] forKey:@"isSelected"];
}

// ========================================
// Run the drive offset calculation routines
- (IBAction) determineDriveReadOffset:(id)sender
{
	
#pragma unused(sender)
	
	ReadOffsetCalculatorSheetController *sheetController = [[ReadOffsetCalculatorSheetController alloc] init];
	
	sheetController.disk = self.disk;
	
	[sheetController beginReadOffsetCalculatorSheetForWindow:self.window 
											   modalDelegate:nil 
											  didEndSelector:NULL 
												 contextInfo:NULL];
}

// ========================================
// Copy the selected tracks to intermediate WAV files, then send to the encoder
- (IBAction) copySelectedTracks:(id)sender
{
	
#pragma unused(sender)

	NSSet *selectedTracks = self.compactDisc.firstSession.selectedTracks;
	if(0 == selectedTracks.count) {
		NSBeep();
		return;
	}

	[self extractTracks:selectedTracks extractionMode:eExtractionModeIndividualTracks];
}

- (IBAction) copyImage:(id)sender
{

#pragma unused(sender)

	[self extractTracks:self.compactDisc.firstSession.tracks extractionMode:eExtractionModeImage];
}

- (IBAction) detectPregaps:(id)sender
{

#pragma unused(sender)
	
	NSSet *selectedTracks = self.compactDisc.firstSession.selectedTracks;
	if(0 == selectedTracks.count) {
		NSBeep();
		return;
	}
	
	DetectPregapsSheetController *sheetController = [[DetectPregapsSheetController alloc] init];
	
	sheetController.disk = self.disk;
	sheetController.trackIDs = [selectedTracks valueForKey:@"objectID"];
	
	[sheetController beginDetectPregapsSheetForWindow:self.window
										modalDelegate:nil 
									   didEndSelector:NULL
										  contextInfo:NULL];
}

- (IBAction) readMCN:(id)sender
{
	
#pragma unused(sender)
	
	ReadMCNSheetController *sheetController = [[ReadMCNSheetController alloc] init];
	
	sheetController.disk = self.disk;
	
	[sheetController beginReadMCNSheetForWindow:self.window
								  modalDelegate:nil 
								 didEndSelector:NULL
									contextInfo:NULL];
}

- (IBAction) readISRCs:(id)sender
{

#pragma unused(sender)
	
	NSSet *selectedTracks = self.compactDisc.firstSession.selectedTracks;
	if(0 == selectedTracks.count) {
		NSBeep();
		return;
	}
	
	ReadISRCsSheetController *sheetController = [[ReadISRCsSheetController alloc] init];
	
	sheetController.disk = self.disk;
	sheetController.trackIDs = [selectedTracks valueForKey:@"objectID"];
	
	[sheetController beginReadISRCsSheetForWindow:self.window
									modalDelegate:nil 
								   didEndSelector:NULL
									  contextInfo:NULL];
}

- (IBAction) createCueSheet:(id)sender
{

#pragma unused(sender)
	
	// Determine where to save the cue
	NSSavePanel *savePanel = [NSSavePanel savePanel];
	
	[savePanel setRequiredFileType:@"cue"];

	// The default directory
	NSURL *baseURL = [[EncoderManager sharedEncoderManager] outputURLForCompactDisc:self.compactDisc];

	[savePanel beginSheetForDirectory:[baseURL path]
								 file:[self.compactDisc.metadata.title stringByReplacingIllegalPathCharactersWithString:@"_"]
					   modalForWindow:self.window
						modalDelegate:self
					   didEndSelector:@selector(createCueSheetSavePanelDidEnd:returnCode:contextInfo:)
						  contextInfo:NULL];	
}

- (IBAction) queryDefaultMusicDatabase:(id)sender
{

#pragma unused(sender)

	NSBundle *defaultMusicDatabaseBundle = [[MusicDatabaseManager sharedMusicDatabaseManager] defaultMusicDatabase];

	// If the default music database wasn't found, try to fail gracefully
	if(!defaultMusicDatabaseBundle) {
		NSBeep();
		NSRunAlertPanel(@"Music Database Not Found", @"The default music database was not found." , @"OK", nil, nil);
		return;
	}

	// Grab the music database's settings dictionary
	NSDictionary *musicDatabaseSettings = [[MusicDatabaseManager sharedMusicDatabaseManager] settingsForMusicDatabase:defaultMusicDatabaseBundle];

	// Instantiate the music database interface
	id <MusicDatabaseInterface> musicDatabaseInterface = [[[defaultMusicDatabaseBundle principalClass] alloc] init];
	
	MusicDatabaseQueryOperation *operation = [musicDatabaseInterface musicDatabaseQueryOperation];
	if(!operation)
		return;

	operation.settings = musicDatabaseSettings;
	operation.discTOC = self.compactDisc.discTOC;
	operation.freeDBDiscID = self.compactDisc.freeDBDiscID;
	operation.musicBrainzDiscID = self.compactDisc.musicBrainzDiscID;
	
	// Observe the operation's progress
	[operation addObserver:self forKeyPath:@"isExecuting" options:NSKeyValueObservingOptionNew context:kMusicDatabaseQueryKVOContext];
	[operation addObserver:self forKeyPath:@"isCancelled" options:NSKeyValueObservingOptionNew context:kMusicDatabaseQueryKVOContext];
	[operation addObserver:self forKeyPath:@"isFinished" options:NSKeyValueObservingOptionNew context:kMusicDatabaseQueryKVOContext];

	[self.operationQueue addOperation:operation];
}

- (IBAction) queryMusicDatabase:(id)sender
{
	NSParameterAssert([sender isKindOfClass:[NSMenuItem class]]);
	NSParameterAssert([[sender representedObject] isKindOfClass:[NSBundle class]]);
	
	NSBundle *musicDatabaseBundle = (NSBundle *)[sender representedObject];

	// Grab the music database's settings dictionary
	NSDictionary *musicDatabaseSettings = [[MusicDatabaseManager sharedMusicDatabaseManager] settingsForMusicDatabase:musicDatabaseBundle];
	
	// Instantiate the music database interface
	id <MusicDatabaseInterface> musicDatabaseInterface = [[[musicDatabaseBundle principalClass] alloc] init];
	
	MusicDatabaseQueryOperation *operation = [musicDatabaseInterface musicDatabaseQueryOperation];
	if(!operation)
		return;

	operation.settings = musicDatabaseSettings;
	operation.discTOC = self.compactDisc.discTOC;
	operation.freeDBDiscID = self.compactDisc.freeDBDiscID;
	operation.musicBrainzDiscID = self.compactDisc.musicBrainzDiscID;
	
	// Observe the operation's progress
	[operation addObserver:self forKeyPath:@"isExecuting" options:NSKeyValueObservingOptionNew context:kMusicDatabaseQueryKVOContext];
	[operation addObserver:self forKeyPath:@"isCancelled" options:NSKeyValueObservingOptionNew context:kMusicDatabaseQueryKVOContext];
	[operation addObserver:self forKeyPath:@"isFinished" options:NSKeyValueObservingOptionNew context:kMusicDatabaseQueryKVOContext];
	
	[self.operationQueue addOperation:operation];	
}

- (IBAction) submitToDefaultMusicDatabase:(id)sender
{
	
#pragma unused(sender)
	
	NSBundle *defaultMusicDatabaseBundle = [[MusicDatabaseManager sharedMusicDatabaseManager] defaultMusicDatabase];
	
	// If the default music database wasn't found, try to fail gracefully
	if(!defaultMusicDatabaseBundle) {
		NSBeep();
		NSRunAlertPanel(@"Music Database Not Found", @"The default music database was not found." , @"OK", nil, nil);
		return;
	}
	
	// Grab the music database's settings dictionary
	NSDictionary *musicDatabaseSettings = [[MusicDatabaseManager sharedMusicDatabaseManager] settingsForMusicDatabase:defaultMusicDatabaseBundle];
	
	// Instantiate the music database interface
	id <MusicDatabaseInterface> musicDatabaseInterface = [[[defaultMusicDatabaseBundle principalClass] alloc] init];
	
	MusicDatabaseSubmissionOperation *operation = [musicDatabaseInterface musicDatabaseSubmissionOperation];
	if(!operation)
		return;
	
	operation.settings = musicDatabaseSettings;
	operation.discTOC = self.compactDisc.discTOC;
	operation.freeDBDiscID = self.compactDisc.freeDBDiscID;
	operation.musicBrainzDiscID = self.compactDisc.musicBrainzDiscID;
	
	// Observe the operation's progress
	[operation addObserver:self forKeyPath:@"isExecuting" options:NSKeyValueObservingOptionNew context:kMusicDatabaseQueryKVOContext];
	[operation addObserver:self forKeyPath:@"isCancelled" options:NSKeyValueObservingOptionNew context:kMusicDatabaseQueryKVOContext];
	[operation addObserver:self forKeyPath:@"isFinished" options:NSKeyValueObservingOptionNew context:kMusicDatabaseQueryKVOContext];
	
	[self.operationQueue addOperation:operation];
}

- (IBAction) submitToMusicDatabase:(id)sender
{
	NSParameterAssert([sender isKindOfClass:[NSMenuItem class]]);
	NSParameterAssert([[sender representedObject] isKindOfClass:[NSBundle class]]);
	
	NSBundle *musicDatabaseBundle = (NSBundle *)[sender representedObject];
	
	// Grab the music database's settings dictionary
	NSDictionary *musicDatabaseSettings = [[MusicDatabaseManager sharedMusicDatabaseManager] settingsForMusicDatabase:musicDatabaseBundle];
	
	// Instantiate the music database interface
	id <MusicDatabaseInterface> musicDatabaseInterface = [[[musicDatabaseBundle principalClass] alloc] init];
	
	MusicDatabaseSubmissionOperation *operation = [musicDatabaseInterface musicDatabaseSubmissionOperation];
	if(!operation)
		return;
	
	operation.settings = musicDatabaseSettings;
	operation.discTOC = self.compactDisc.discTOC;
	operation.freeDBDiscID = self.compactDisc.freeDBDiscID;
	operation.musicBrainzDiscID = self.compactDisc.musicBrainzDiscID;
	
	[self.operationQueue addOperation:operation];
}

- (IBAction) searchForMetadata:(id)sender
{
	NSParameterAssert([sender isKindOfClass:[NSMenuItem class]]);
	NSParameterAssert([[sender representedObject] isKindOfClass:[NSBundle class]]);
	
	NSBundle *metadataSourceBundle = (NSBundle *)[sender representedObject];
	
	// Grab the metadata source's settings dictionary
	NSDictionary *metadataSourceSettings = [[MetadataSourceManager sharedMetadataSourceManager] settingsForMetadataSource:metadataSourceBundle];
	
	// Instantiate the metadata source interface
	id <MetadataSourceInterface> metadataSourceInterface = [[[metadataSourceBundle principalClass] alloc] init];
	
	NSViewController *viewController = [metadataSourceInterface metadataSourceViewController];
	if(!viewController)
		return;

	MetadataSourceData *metadataSourceData = [[MetadataSourceData alloc] init];
	
	metadataSourceData.discTOC = self.compactDisc.discTOC;
	metadataSourceData.freeDBDiscID = self.compactDisc.freeDBDiscID;
	metadataSourceData.musicBrainzDiscID = self.compactDisc.musicBrainzDiscID;
	metadataSourceData.settings = metadataSourceSettings;
	metadataSourceData.metadata = metadataForCompactDisc(self.compactDisc);
	metadataSourceData.delegate = self;
	
	[viewController setRepresentedObject:metadataSourceData];

	// Swap in the metadata view
	[self swapMainViewController:_metadataViewController withViewController:viewController];
}

- (IBAction) queryAccurateRip:(id)sender
{

#pragma unused(sender)

	AccurateRipQueryOperation *operation = [[AccurateRipQueryOperation alloc] init];
	if(!operation)
		return;

	operation.compactDiscID = self.compactDisc.objectID;

	// Observe the operation's progress
	[operation addObserver:self forKeyPath:@"isExecuting" options:NSKeyValueObservingOptionNew context:kAccurateRipQueryKVOContext];
	[operation addObserver:self forKeyPath:@"isCancelled" options:NSKeyValueObservingOptionNew context:kAccurateRipQueryKVOContext];
	[operation addObserver:self forKeyPath:@"isFinished" options:NSKeyValueObservingOptionNew context:kAccurateRipQueryKVOContext];

	[self.operationQueue addOperation:operation];
}

- (IBAction) ejectDisc:(id)sender
{

#pragma unused(sender)

	// Register the unmount request- if it is successful the unmount callback will perform the eject
	DADiskUnmount(self.disk, kDADiskUnmountOptionWhole, unmountCallback, self);
}

@end

@implementation CompactDiscWindowController (SheetCallbacks)

- (void) showMusicDatabaseMatchesSheetDidEnd:(NSWindow *)sheet returnCode:(int)returnCode contextInfo:(void *)contextInfo
{
	NSParameterAssert(nil != sheet);
	NSParameterAssert(NULL != contextInfo);

	[sheet orderOut:self];
	
	MusicDatabaseMatchesSheetController *sheetController = (MusicDatabaseMatchesSheetController *)contextInfo;
	
	if(NSOKButton == returnCode)
		[self updateMetadataWithMusicDatabaseEntry:sheetController.selectedMatch];
}

- (void) createCueSheetSavePanelDidEnd:(NSSavePanel *)sheet returnCode:(int)returnCode  contextInfo:(void *)contextInfo
{
	
#pragma unused(contextInfo)
	
	if(NSCancelButton == returnCode)
		return;
	
	NSURL *cueSheetURL = [sheet URL];
	
	NSError *error = nil;
	if(![self.compactDisc writeCueSheetToURL:cueSheetURL error:&error])
		[self presentError:error modalForWindow:self.window delegate:nil didPresentSelector:NULL contextInfo:NULL];
}

- (void) showSuccessfulExtractionSheetDidEnd:(NSWindow *)sheet returnCode:(int)returnCode contextInfo:(void *)contextInfo
{
	
	NSURL *logFileURL = (NSURL *)contextInfo;
	
	[sheet orderOut:self];
	
	// Details
	if(NSAlertAlternateReturn == returnCode)
		[[NSWorkspace sharedWorkspace] openURL:logFileURL];
	
}

@end

@implementation CompactDiscWindowController (ExtractionViewControllerMethods)

- (void) extractionFinishedWithReturnCode:(int)returnCode
{	
	// Replace the extraction view with the metadata view
	[self swapMainViewController:_extractionViewController withViewController:_metadataViewController];
	
	if(NSCancelButton == returnCode)
		return;
	
	// Alert the user if any tracks failed to extract
	if([_extractionViewController.failedTrackIDs count]) {
		// Fetch the tracks that failed and sort them by track number
		NSPredicate *trackPredicate  = [NSPredicate predicateWithFormat:@"self IN %@", _extractionViewController.failedTrackIDs];
		NSSortDescriptor *trackNumberSortDescriptor = [[NSSortDescriptor alloc] initWithKey:@"number" ascending:YES];
		NSEntityDescription *trackEntityDescription = [NSEntityDescription entityForName:@"TrackDescriptor" inManagedObjectContext:self.managedObjectContext];
		
		NSFetchRequest *trackFetchRequest = [[NSFetchRequest alloc] init];
		
		[trackFetchRequest setEntity:trackEntityDescription];
		[trackFetchRequest setPredicate:trackPredicate];
		[trackFetchRequest setSortDescriptors:[NSArray arrayWithObject:trackNumberSortDescriptor]];
		
		NSError *error = nil;
		NSArray *tracks = [self.managedObjectContext executeFetchRequest:trackFetchRequest error:&error];
		if(!tracks) {
			[self presentError:error modalForWindow:self.window delegate:self didPresentSelector:@selector(didPresentErrorWithRecovery:contextInfo:) contextInfo:NULL];
			return;
		}
		
		NSString *albumTitle = self.compactDisc.metadata.title;
		if(!albumTitle)
			albumTitle = NSLocalizedString(@"Unknown Album", @"");
		
		NSArray *trackTitles = [tracks valueForKeyPath:@"metadata.title"];
		NSString *trackTitlesString = [trackTitles componentsJoinedByString:@", "];
		NSString *alertMessage = nil;
		if(eExtractionModeImage == _extractionViewController.extractionMode)
			alertMessage = [NSString stringWithFormat:NSLocalizedString(@"The image of \u201c%@\u201d could not be created because read errors occurred during audio extraction.", @""), albumTitle];
		else
			alertMessage = [NSString stringWithFormat:NSLocalizedString(@"Some tracks from \u201c%@\u201d could not be copied because read errors occurred during audio extraction.", @""), albumTitle];
		NSBeginCriticalAlertSheet(alertMessage,
								  NSLocalizedString(@"OK", @"Button"),
								  nil,
								  nil,
								  self.window,
								  nil,
								  NULL,
								  NULL,
								  NULL, 
								  NSLocalizedString(@"Unrecoverable read errors occurred for the following tracks: %@", @""),
								  trackTitlesString);
	}
	
	// Save an extraction log file if any tracks (in track mode) or the image (in the image mode) were/was successfully extracted
	if((eExtractionModeImage == _extractionViewController.extractionMode && !_extractionViewController.imageExtractionRecord) || (eExtractionModeIndividualTracks == _extractionViewController.extractionMode && ![_extractionViewController.trackExtractionRecords count]))
		return;
	
	NSString *title = self.compactDisc.metadata.title;
	if(nil == title)
		title = NSLocalizedString(@"Unknown Album", @"");
	
	NSURL *baseURL = [[EncoderManager sharedEncoderManager] outputURLForCompactDisc:self.compactDisc];
	NSString *filename = [title stringByReplacingIllegalPathCharactersWithString:@"_"];
	NSString *pathname = [filename stringByAppendingPathExtension:@"log"];
	NSString *outputPath = [[baseURL path] stringByAppendingPathComponent:pathname];
	NSURL *logFileURL = [NSURL fileURLWithPath:outputPath];
	
	// Don't overwrite existing log files
	if([[NSFileManager defaultManager] fileExistsAtPath:[logFileURL path]]) {
		
		NSString *backupFilename = [filename copy];
		NSString *backupPathname = nil;
		NSString *backupPath = nil;
		
		do {
			backupFilename = [backupFilename stringByAppendingPathExtension:@"old"];
			backupPathname = [backupFilename stringByAppendingPathExtension:@"log"];
			backupPath = [[baseURL path] stringByAppendingPathComponent:backupPathname];
		} while([[NSFileManager defaultManager] fileExistsAtPath:backupPath]);
		
		[[NSFileManager defaultManager] movePath:[logFileURL path] toPath:backupPath handler:nil];
	}
	
	NSError *error = nil;
	if(eExtractionModeImage == _extractionViewController.extractionMode) {
		if(![self writeLogFileToURL:logFileURL imageExtractionRecord:_extractionViewController.imageExtractionRecord error:&error])
			[self presentError:error modalForWindow:self.window delegate:nil didPresentSelector:NULL contextInfo:NULL];
	}
	else {
		if(![self writeLogFileToURL:logFileURL trackExtractionRecords:_extractionViewController.trackExtractionRecords error:&error])
			[self presentError:error modalForWindow:self.window delegate:nil didPresentSelector:NULL contextInfo:NULL];
	}
	
	// Save a cue sheet
//	pathname = [filename stringByAppendingPathExtension:@"cue"];
//	outputPath = [[baseURL path] stringByAppendingPathComponent:pathname];
//	NSURL *cueSheetURL = [NSURL fileURLWithPath:outputPath];
//	
//	if(![self.compactDisc writeCueSheetToURL:cueSheetURL error:&error])
//		[self presentError:error modalForWindow:self.window delegate:nil didPresentSelector:NULL contextInfo:NULL];
	
	if(![_extractionViewController.failedTrackIDs count]) {
		// Create a sheet that will auto-dismiss notifying the user that the extraction was successful
		NSPanel *panel = NSGetAlertPanel(NSLocalizedString(@"Success!", @""),
										 NSLocalizedString(@"All tracks were successfully extracted.", @""),
										 NSLocalizedString(@"OK", @"Button"),
										 NSLocalizedString(@"Details", @"Button"),
										 nil);
		
		[[NSApplication sharedApplication] beginSheet:panel 
									   modalForWindow:self.window 
										modalDelegate:self 
									   didEndSelector:@selector(showSuccessfulExtractionSheetDidEnd:returnCode:contextInfo:) 
										  contextInfo:logFileURL];
		
		NSReleaseAlertPanel(panel);
		
		[NSTimer scheduledTimerWithTimeInterval:3.0 
										 target:self 
									   selector:@selector(showSuccessfulExtractionSheetDismissalTimerFired:) 
									   userInfo:[NSArray arrayWithObject:panel] 
										repeats:NO];
	}
	
}

@end

@implementation CompactDiscWindowController (Private)

- (void) diskWasEjected
{
	[self.window performClose:nil];
}

- (void) updateMetadataWithMusicDatabaseEntry:(id)musicDatabaseEntry
{
	NSParameterAssert(nil != musicDatabaseEntry);

	// Indicates whether nil metadata values in this query should overwrite existing values
	BOOL eraseExistingMetadata = [[NSUserDefaults standardUserDefaults] boolForKey:@"OverwriteAllMetadata"];
	
	// Set the album's metadata
	if(eraseExistingMetadata || [musicDatabaseEntry valueForKey:kMetadataAdditionalMetadataKey])
		self.compactDisc.metadata.additionalMetadata = [musicDatabaseEntry valueForKey:kMetadataAdditionalMetadataKey];
	if(eraseExistingMetadata || [musicDatabaseEntry valueForKey:kMetadataAlbumArtistKey])
		self.compactDisc.metadata.artist = [musicDatabaseEntry valueForKey:kMetadataAlbumArtistKey];
	if(eraseExistingMetadata || [musicDatabaseEntry valueForKey:kMetadataReleaseDateKey])
		self.compactDisc.metadata.date = [musicDatabaseEntry valueForKey:kMetadataReleaseDateKey];
	if(eraseExistingMetadata || [musicDatabaseEntry valueForKey:kMetadataDiscNumberKey])
		self.compactDisc.metadata.discNumber = [musicDatabaseEntry valueForKey:kMetadataDiscNumberKey];
	if(eraseExistingMetadata || [musicDatabaseEntry valueForKey:kMetadataDiscTotalKey])
		self.compactDisc.metadata.discTotal = [musicDatabaseEntry valueForKey:kMetadataDiscTotalKey];
	if(eraseExistingMetadata || [musicDatabaseEntry valueForKey:kMetadataCompilationKey])
		self.compactDisc.metadata.isCompilation = [musicDatabaseEntry valueForKey:kMetadataCompilationKey];
	if(eraseExistingMetadata || [musicDatabaseEntry valueForKey:kMetadataMCNKey])
		self.compactDisc.metadata.MCN = [musicDatabaseEntry valueForKey:kMetadataMCNKey];
	if(eraseExistingMetadata || [musicDatabaseEntry valueForKey:kMetadataMusicBrainzIDKey])
		self.compactDisc.metadata.musicBrainzID = [musicDatabaseEntry valueForKey:kMetadataMusicBrainzIDKey];
	if(eraseExistingMetadata || [musicDatabaseEntry valueForKey:kMetadataAlbumTitleKey])
		self.compactDisc.metadata.title = [musicDatabaseEntry valueForKey:kMetadataAlbumTitleKey];

	// Set each track's metadata
	NSArray *trackMetadataArray = [musicDatabaseEntry valueForKey:kTrackMetadataArrayKey];
	for(id trackMetadata in trackMetadataArray) {
		NSUInteger trackNumber = [[trackMetadata valueForKey:kMetadataTrackNumberKey] unsignedIntegerValue];
		
		TrackDescriptor *track = [self.compactDisc.firstSession trackNumber:trackNumber];
		if(!track)
			continue;
		
		if(eraseExistingMetadata || [trackMetadata valueForKey:kMetadataAdditionalMetadataKey])
			track.metadata.additionalMetadata = [trackMetadata valueForKey:kMetadataAdditionalMetadataKey];
		if(eraseExistingMetadata || [trackMetadata valueForKey:kMetadataArtistKey])
			track.metadata.artist = [trackMetadata valueForKey:kMetadataArtistKey];
		if(eraseExistingMetadata || [trackMetadata valueForKey:kMetadataComposerKey])
			track.metadata.composer = [trackMetadata valueForKey:kMetadataComposerKey];
		if(eraseExistingMetadata || [trackMetadata valueForKey:kMetadataReleaseDateKey])
			track.metadata.date = [trackMetadata valueForKey:kMetadataReleaseDateKey];
		if(eraseExistingMetadata || [trackMetadata valueForKey:kMetadataGenreKey])
			track.metadata.genre = [trackMetadata valueForKey:kMetadataGenreKey];
		if(eraseExistingMetadata || [trackMetadata valueForKey:kMetadataISRCKey])
			track.metadata.ISRC = [trackMetadata valueForKey:kMetadataISRCKey];
		if(eraseExistingMetadata || [trackMetadata valueForKey:kMetadataLyricsKey])
			track.metadata.lyrics = [trackMetadata valueForKey:kMetadataLyricsKey];
		if(eraseExistingMetadata || [trackMetadata valueForKey:kMetadataMusicBrainzIDKey])
			track.metadata.musicBrainzID = [trackMetadata valueForKey:kMetadataMusicBrainzIDKey];
		if(eraseExistingMetadata || [trackMetadata valueForKey:kMetadataTitleKey])
			track.metadata.title = [trackMetadata valueForKey:kMetadataTitleKey];
	}
	
	// Save the metadata
	NSError *error = nil;
	if([self.managedObjectContext hasChanges] && ![self.managedObjectContext save:&error])
		[self presentError:error modalForWindow:self.window delegate:nil didPresentSelector:NULL contextInfo:NULL];
}

- (void) toggleTableColumnVisible:(id)sender
{
	NSParameterAssert(nil != sender);
	NSParameterAssert([sender isKindOfClass:[NSMenuItem class]]);
	
	NSMenuItem *menuItem = (NSMenuItem *)sender;
	NSTableColumn *column = menuItem.representedObject;
	
	[column setHidden:!column.isHidden];
	[menuItem setState:!column.isHidden];
}

- (void) accurateRipQueryOperationDidReturn:(AccurateRipQueryOperation *)operation
{
	NSParameterAssert(nil != operation);
	
	if(operation.error) {
		[self presentError:operation.error modalForWindow:self.window delegate:nil didPresentSelector:NULL contextInfo:NULL];
		return;
	}
	
	if(![self.compactDisc.accurateRipDiscs count]) {
		NSBeginAlertSheet(NSLocalizedString(@"The disc was not found.", @"Music database search failed"), 
						  NSLocalizedString(@"OK", @"Button"),
						  nil, /* alternateButton */
						  nil, /* otherButton */
						  self.window, 
						  nil, /* modalDelegate */
						  NULL, /* didEndSelector */
						  NULL, /* didDismissSelector */
						  NULL, /* contextInfo */
						  NSLocalizedString(@"No matching discs were found in the AccurateRip database.", @""));
	}
}

- (void) musicDatabaseQueryOperationDidReturn:(MusicDatabaseQueryOperation *)operation
{
	NSParameterAssert(nil != operation);
	
	if(operation.error) {
		[self presentError:operation.error modalForWindow:self.window delegate:nil didPresentSelector:NULL contextInfo:NULL];
		return;
	}
	
	NSUInteger matchCount = operation.queryResults.count;

	if(0 == matchCount) {
		NSBeginAlertSheet(NSLocalizedString(@"The disc was not found.", @"Music database search failed"), 
						  NSLocalizedString(@"OK", @"Button"),
						  nil, /* alternateButton */
						  nil, /* otherButton */
						  self.window, 
						  nil, /* modalDelegate */
						  NULL, /* didEndSelector */
						  NULL, /* didDismissSelector */
						  NULL, /* contextInfo */
						  NSLocalizedString(@"No matching discs were found in the database.", @""));
	}
	else if(1 == matchCount)
		[self updateMetadataWithMusicDatabaseEntry:operation.queryResults.lastObject];
	else {
		MusicDatabaseMatchesSheetController *sheetController = [[MusicDatabaseMatchesSheetController alloc] init];		
		sheetController.matches = operation.queryResults;
		
		[sheetController beginMusicDatabaseMatchesSheetForWindow:self.window 
												   modalDelegate:self
												  didEndSelector:@selector(showMusicDatabaseMatchesSheetDidEnd:returnCode:contextInfo:) 
													 contextInfo:sheetController];
	}
}

- (void) extractTracks:(NSSet *)tracks extractionMode:(eExtractionMode)extractionMode
{
	NSParameterAssert(nil != tracks);
	
	// Save the metadata
	NSError *error = nil;
	if([self.managedObjectContext hasChanges] && ![self.managedObjectContext save:&error])
		[self presentError:error modalForWindow:self.window delegate:nil didPresentSelector:NULL contextInfo:NULL];
	
	// Set the view's frame, so when added it will have the correct size (views are not auto-sized when added)
	[self swapMainViewController:_metadataViewController withViewController:_extractionViewController];
	
	// Set up the audio extraction parameters
	_extractionViewController.disk = self.disk;
	_extractionViewController.extractionMode = extractionMode;
	_extractionViewController.trackIDs = [tracks valueForKey:@"objectID"];
	
	_extractionViewController.maxRetries = [[NSUserDefaults standardUserDefaults] integerForKey:@"maxRetries"];
	_extractionViewController.requiredSectorMatches = [[NSUserDefaults standardUserDefaults] integerForKey:@"requiredSectorMatches"];
	_extractionViewController.requiredTrackMatches = [[NSUserDefaults standardUserDefaults] integerForKey:@"requiredTrackMatches"];
	
	// Start extracting
	[_extractionViewController extract:self];
}

- (void) showSuccessfulExtractionSheetDismissalTimerFired:(NSTimer *)timer
{
	NSPanel *panel = [[timer userInfo] lastObject];
	[[NSApplication sharedApplication] endSheet:panel returnCode:NSAlertDefaultReturn];
}

- (void) swapMainViewController:(NSViewController *)oldViewController withViewController:(NSViewController *)newViewController
{
	NSParameterAssert(nil != oldViewController);
	NSParameterAssert(nil != newViewController);
	NSParameterAssert(oldViewController != newViewController);
	
	// Make sure the view to be swapped in has the same frame as the old view
	[[newViewController view] setFrame:[[oldViewController view] frame]];
	
	[_mainView replaceSubview:[oldViewController view] with:[newViewController view]];
	
	// Ensure the view controller and its view are the next responders
	[self setNextResponder:newViewController];
	
	NSView *view = [[newViewController view] nextValidKeyView];
	if(view)
		[[self window] makeFirstResponder:view];
}

@end
