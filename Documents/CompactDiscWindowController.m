/*
 *  Copyright (C) 2007 Stephen F. Booth <me@sbooth.org>
 *  All Rights Reserved
 */

#import "CompactDiscWindowController.h"

#import "CompactDisc.h"
#import "SessionDescriptor.h"
#import "TrackDescriptor.h"
#import "AlbumMetadata.h"
#import "TrackMetadata.h"

#import "AccurateRipQueryOperation.h"
#import "AccurateRipDiscRecord.h"
#import "AccurateRipTrackRecord.h"
#import "AccurateRipUtilities.h"

#import "DriveInformation.h"

#import "BitArray.h"
#import "SectorRange.h"
#import "ExtractionOperation.h"
#import "ExtractionRecord.h"
#import "ExtractedTrackRecord.h"

#import "PreGapDetectionOperation.h"

#import "MusicDatabaseQueryOperation.h"
#import "MusicDatabaseMatchesSheetController.h"

#import "ExtractionConfigurationSheetController.h"
#import "KBPopUpToolbarItem.h"

#define WINDOW_BORDER_THICKNESS ((CGFloat)20)

// ========================================
// Context objects for observeValueForKeyPath:ofObject:change:context:
// ========================================
NSString * const	kCompactDiscOperationQueueKVOContext	= @"org.sbooth.Rip.CompactDiscWindowController.CompactDiscOperationQueue.KVOContext";
NSString * const	kNetworkOperationQueueKVOContext		= @"org.sbooth.Rip.CompactDiscWindowController.NetworkOperationQueue.KVOContext";

@interface CompactDiscWindowController ()
@property (assign) CompactDisc * compactDisc;
@property (assign) DriveInformation * driveInformation;
@end

@interface CompactDiscWindowController (Private)
- (void) extractionOperationStarted:(ExtractionOperation *)operation;
- (void) extractionOperationStopped:(ExtractionOperation *)operation;
- (void) preGapDetectionOperationStarted:(PreGapDetectionOperation *)operation;
- (void) preGapDetectionOperationStopped:(PreGapDetectionOperation *)operation;
- (void) accurateRipQueryOperationStarted:(AccurateRipQueryOperation *)operation;
- (void) accurateRipQueryOperationStopped:(AccurateRipQueryOperation *)operation;
- (void) musicDatabaseQueryOperationStarted:(MusicDatabaseQueryOperation *)operation;
- (void) musicDatabaseQueryOperationStopped:(MusicDatabaseQueryOperation *)operation;
- (void) diskWasEjected;
- (void) showMusicDatabaseMatchesSheetDidEnd:(NSWindow *)sheet returnCode:(int)returnCode contextInfo:(void *)contextInfo;
- (void) updateMetadataWithMusicDatabaseEntry:(id)musicDatabaseEntry;
@end

// ========================================
// DiskArbitration eject callback
// ========================================
void ejectCallback(DADiskRef disk, DADissenterRef dissenter, void *context);
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

@synthesize trackController = _trackController;
@synthesize driveInformationController = _driveInformationController;
@synthesize compactDiscOperationQueue = _compactDiscOperationQueue;
@synthesize networkOperationQueue = _networkOperationQueue;

@synthesize disk = _disk;
@synthesize compactDisc = _compactDisc;
@synthesize driveInformation = _driveInformation;

- (id) init
{
	if((self = [super initWithWindowNibName:@"CompactDisc"])) {
		_compactDiscOperationQueue = [[NSOperationQueue alloc] init];
		_networkOperationQueue = [[NSOperationQueue alloc] init];

		// Only allow one compact disc operation at a time
		[self.compactDiscOperationQueue setMaxConcurrentOperationCount:1];
		
		// Observe changes in the compact disc operations array, to be notified when each operation starts and stops
		[self.compactDiscOperationQueue addObserver:self forKeyPath:@"operations" options:(NSKeyValueObservingOptionOld |  NSKeyValueObservingOptionNew) context:kCompactDiscOperationQueueKVOContext];

		// Observe changes in the network operations array, to be notified when each operation starts and stops
		[self.networkOperationQueue addObserver:self forKeyPath:@"operations" options:(NSKeyValueObservingOptionOld |  NSKeyValueObservingOptionNew) context:kNetworkOperationQueueKVOContext];
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
	// Our window has a bottom border used to display the AccurateRip availability for this disc and total playing time
	[self.window setAutorecalculatesContentBorderThickness:YES forEdge:NSMinYEdge];
	[self.window setContentBorderThickness:WINDOW_BORDER_THICKNESS forEdge:NSMinYEdge];
	
	// Set the default sort descriptors for the track table
	NSSortDescriptor *trackNumberSortDescriptor = [[NSSortDescriptor alloc] initWithKey:@"number" ascending:YES];
	[self.trackController setSortDescriptors:[NSArray arrayWithObject:trackNumberSortDescriptor]];
}

- (BOOL) validateMenuItem:(NSMenuItem *)menuItem
{
	if([menuItem action] == @selector(copySelectedTracks:))
		return (0 != self.compactDisc.firstSession.selectedTracks.count);
	else if([menuItem action] == @selector(copyImage:))
		return YES;
	else if([menuItem action] == @selector(queryDefaultMusicDatabase:))
		return YES;
	else if([menuItem action] == @selector(queryFreeDB:))
		return YES;
	else if([menuItem action] == @selector(queryMusicBrainz:))
		return YES;
	else if([menuItem action] == @selector(queryiTunes:))
		return YES;
	else if([menuItem action] == @selector(queryAccurateRip:))
		return YES;
	else if([menuItem action] == @selector(detectPreGaps:))
		return (0 != self.compactDisc.firstSession.selectedTracks.count);
	else
		return [super validateMenuItem:menuItem];
}

- (BOOL) validateToolbarItem:(NSToolbarItem *)toolbarItem
{
	if([toolbarItem action] == @selector(copySelectedTracks:))
		return (0 != self.compactDisc.firstSession.selectedTracks.count);
	else if([toolbarItem action] == @selector(copyImage:))
		return YES;
	else if([toolbarItem action] == @selector(queryDefaultMusicDatabase:))
		return YES;
	else if([toolbarItem action] == @selector(queryFreeDB:))
		return YES;
	else if([toolbarItem action] == @selector(queryMusicBrainz:))
		return YES;
	else if([toolbarItem action] == @selector(queryiTunes:))
		return YES;
	else if([toolbarItem action] == @selector(queryAccurateRip:))
		return YES;
	else if([toolbarItem action] == @selector(detectPreGaps:))
		return (0 != self.compactDisc.firstSession.selectedTracks.count);
	else
		return [super validateToolbarItem:toolbarItem];
}

- (void) observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context
{
	// Compact Disc operations
	if(kCompactDiscOperationQueueKVOContext == context) {
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
	// Network operations
	else if(kNetworkOperationQueueKVOContext == context) {
		NSInteger changeKind = [[change objectForKey:NSKeyValueChangeKindKey] integerValue];
		
		if(NSKeyValueChangeInsertion == changeKind) {
			for(NSOperation *operation in [change objectForKey:NSKeyValueChangeNewKey]) {
				if([operation isKindOfClass:[AccurateRipQueryOperation class]])
					[self accurateRipQueryOperationStarted:(AccurateRipQueryOperation *)operation];
				else if([operation isKindOfClass:[MusicDatabaseQueryOperation class]])
					[self musicDatabaseQueryOperationStarted:(MusicDatabaseQueryOperation *)operation];
			}
		}
		else if(NSKeyValueChangeRemoval == changeKind) {
			for(NSOperation *operation in [change objectForKey:NSKeyValueChangeOldKey])
				if([operation isKindOfClass:[AccurateRipQueryOperation class]])
					[self accurateRipQueryOperationStopped:(AccurateRipQueryOperation *)operation];
				else if([operation isKindOfClass:[MusicDatabaseQueryOperation class]])
					[self musicDatabaseQueryOperationStopped:(MusicDatabaseQueryOperation *)operation];
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

#pragma mark NSWindow Delegate Methods

- (NSUndoManager *) windowWillReturnUndoManager:(NSWindow *)window
{
	
#pragma unused(window)
	
	return self.managedObjectContext.undoManager;
}

- (void) setDisk:(DADiskRef)disk
{
	if(disk != _disk) {
		if(_disk)
			CFRelease(_disk), _disk = NULL;
		
		self.compactDisc = nil;
		self.driveInformation = nil;
		
		if(disk) {
			_disk = DADiskCopyWholeDisk(disk);
			self.compactDisc = [CompactDisc compactDiscWithDADiskRef:self.disk inManagedObjectContext:self.managedObjectContext];
			self.driveInformation = [DriveInformation driveInformationWithDADiskRef:self.disk inManagedObjectContext:self.managedObjectContext];

			if(!self.driveInformation.readOffset)
				NSLog(@"Read offset is not configured for drive %@", self.driveInformation.deviceIdentifier);
			
			self.driveInformation.readOffset = [NSNumber numberWithInt:102];
		}
	}
}

#pragma mark NSTableView Delegate Methods

- (void) tableView:(NSTableView *)aTableView willDisplayCell:(id)aCell forTableColumn:(NSTableColumn *)aTableColumn row:(NSInteger)rowIndex
{

#pragma unused(aTableView)

	if([aTableColumn.identifier isEqualToString:@"isSelected"])
		[aCell setTitle:[[[_trackController.arrangedObjects objectAtIndex:rowIndex] valueForKey:@"number"] stringValue]];
}

#pragma mark NSToolbar Delegate Methods

- (NSToolbarItem *) toolbar:(NSToolbar *)toolbar itemForItemIdentifier:(NSString *)itemIdentifier willBeInsertedIntoToolbar:(BOOL)flag
{
	NSLog(@"%@",itemIdentifier);

	if([itemIdentifier isEqualToString:@"fnord"]) {
		KBPopUpToolbarItem *toolbarItem = [[KBPopUpToolbarItem alloc] initWithItemIdentifier:itemIdentifier];
		
		toolbarItem.image = [NSImage imageNamed:@"NSInfo"];
		
		toolbarItem.target = self;
		toolbarItem.action = @selector(queryDefaultMusicDatabase:);
		
		toolbarItem.label = @"fnord";
		toolbarItem.paletteLabel = @"fnord";
		toolbarItem.toolTip = @"fnord";
		
		NSMenu *toolbarItemMenu = [[NSMenu alloc] initWithTitle:@"fnord"];
		[toolbarItemMenu addItemWithTitle:@"FreeDB" action:@selector(queryFreeDB:) keyEquivalent:@""];
		[toolbarItemMenu addItemWithTitle:@"MusicBrainz" action:@selector(queryMusicBrainz:) keyEquivalent:@""];
		[toolbarItemMenu addItemWithTitle:@"iTunes" action:@selector(queryiTunes:) keyEquivalent:@""];
		
		toolbarItem.menu = toolbarItemMenu;
		
		return toolbarItem;
	}
	
	return nil;
}

- (NSArray *) toolbarAllowedItemIdentifiers:(NSToolbar *)toolbar
{
	return [NSArray arrayWithObject:@"fnord"];
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
// Copy the selected tracks to intermediate WAV files, then to the encoder
- (IBAction) copySelectedTracks:(id)sender
{
	
#pragma unused(sender)
	
	SessionDescriptor *firstSession = self.compactDisc.firstSession;
	NSSet *selectedTracks = firstSession.selectedTracks;
	
	if(0 == selectedTracks.count) {
		NSBeep();
		return;
	}
	
	for(TrackDescriptor *track in selectedTracks) {
		ExtractionOperation *trackExtractionOperation = [[ExtractionOperation alloc] init];
		
		trackExtractionOperation.disk = self.disk;
		trackExtractionOperation.sectors = track.sectorRange;
		trackExtractionOperation.allowedSectors = self.compactDisc.firstSession.sectorRange;
		trackExtractionOperation.trackIDs = [NSArray arrayWithObject:track.objectID];
		trackExtractionOperation.readOffset = self.driveInformation.readOffset;
		trackExtractionOperation.URL = [NSURL fileURLWithPath:[NSString stringWithFormat:@"/tmp/Track %@.wav", track.number]];
		
		[self.compactDiscOperationQueue addOperation:trackExtractionOperation];
	}
}

- (IBAction) copyImage:(id)sender
{

#pragma unused(sender)

	ExtractionConfigurationSheetController *extractionConfigurationSheetController = [[ExtractionConfigurationSheetController alloc] init];
	
	[[NSApplication sharedApplication] beginSheet:[extractionConfigurationSheetController window] 
								   modalForWindow:self.window 
									modalDelegate:self 
								   didEndSelector:@selector(showStreamInformationSheetDidEnd:returnCode:contextInfo:) 
									  contextInfo:extractionConfigurationSheetController];

	/*
	SectorRange *imageSectorRange = [SectorRange sectorRangeWithFirstSector:[self.compactDisc firstSectorForSession:1]
																 lastSector:[self.compactDisc lastSectorForSession:1]];
	
	ExtractionOperation *imageExtractionOperation = [[ExtractionOperation alloc] init];
	
	imageExtractionOperation.disk = self.disk;
	imageExtractionOperation.sectors = imageSectorRange;
	imageExtractionOperation.allowedSectors = self.compactDisc.firstSession.sectorRange;
	imageExtractionOperation.trackIDs = [self.compactDisc.firstSession.tracks valueForKey:@"objectID"];
	imageExtractionOperation.readOffset = self.driveInformation.readOffset;
	imageExtractionOperation.url = [NSURL fileURLWithPath:@"/tmp/Disc Image.wav"];
	
	[self.compactDiscOperationQueue addOperation:imageExtractionOperation];
	 */
}

- (IBAction) detectPreGaps:(id)sender
{

#pragma unused(sender)
	
	NSSet *selectedTracks = self.compactDisc.firstSession.selectedTracks;
	
	if(0 == selectedTracks.count) {
		NSBeep();
		return;
	}
	
	for(TrackDescriptor *track in selectedTracks) {
		PreGapDetectionOperation *preGapDetectionOperation = [[PreGapDetectionOperation alloc] init];
		
		preGapDetectionOperation.disk = self.disk;
		preGapDetectionOperation.trackID = track.objectID;
		
		[self.compactDiscOperationQueue addOperation:preGapDetectionOperation];
	}
}

- (IBAction) queryDefaultMusicDatabase:(id)sender
{

#pragma unused(sender)

	MusicDatabaseQueryOperation *operation = [MusicDatabaseQueryOperation defaultMusicDatabaseQueryOperation];
	operation.compactDiscID = self.compactDisc.objectID;
	
	[self.networkOperationQueue addOperation:operation];
}

- (IBAction) queryFreeDB:(id)sender
{
	
#pragma unused(sender)
	
	MusicDatabaseQueryOperation *operation = [MusicDatabaseQueryOperation FreeDBQueryOperation];
	operation.compactDiscID = self.compactDisc.objectID;
	
	[self.networkOperationQueue addOperation:operation];
}

- (IBAction) queryMusicBrainz:(id)sender
{
	
#pragma unused(sender)
	
	MusicDatabaseQueryOperation *operation = [MusicDatabaseQueryOperation MusicBrainzQueryOperation];
	operation.compactDiscID = self.compactDisc.objectID;
	
	[self.networkOperationQueue addOperation:operation];
}

- (IBAction) queryiTunes:(id)sender
{
	
#pragma unused(sender)
	
	MusicDatabaseQueryOperation *operation = [MusicDatabaseQueryOperation iTunesQueryOperation];
	operation.compactDiscID = self.compactDisc.objectID;
	
	[self.networkOperationQueue addOperation:operation];
}

- (IBAction) queryAccurateRip:(id)sender
{

#pragma unused(sender)

	AccurateRipQueryOperation *operation = [[AccurateRipQueryOperation alloc] init];
	operation.compactDiscID = self.compactDisc.objectID;
	
	[self.networkOperationQueue addOperation:operation];
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

@end

@implementation CompactDiscWindowController (Private)

- (void) extractionOperationStarted:(ExtractionOperation *)operation
{
	NSParameterAssert(nil != operation);

#if DEBUG
	NSLog(@"Extraction to %@ started", operation.URL.path);
#endif
}

- (void) extractionOperationStopped:(ExtractionOperation *)operation
{
	NSParameterAssert(nil != operation);
	
	// Delete the output file if the operation was cancelled or did not succeed
	if(operation.error || operation.isCancelled) {
		if(operation.error)
			[self presentError:operation.error modalForWindow:self.window delegate:nil didPresentSelector:NULL contextInfo:NULL];
			
		NSError *error = nil;
		if(![[NSFileManager defaultManager] removeItemAtPath:operation.URL.path error:&error])
			[self presentError:error modalForWindow:self.window delegate:nil didPresentSelector:NULL contextInfo:NULL];
		return;
	}

#if DEBUG
	NSLog(@"Extraction to %@ finished, %u C2 errors.  MD5 = %@", operation.URL.path, operation.errorFlags.countOfOnes, operation.MD5);
#endif
	
	ExtractionRecord *extractionRecord = [NSEntityDescription insertNewObjectForEntityForName:@"ExtractionRecord" 
																	   inManagedObjectContext:self.managedObjectContext];
	
	extractionRecord.disc = self.compactDisc;
	extractionRecord.date = [NSDate date];
	extractionRecord.drive = self.driveInformation;
	extractionRecord.URL = operation.URL.absoluteString;
//	extractionRecord setValue:operation.errorFlags forKey:@"errorFlags"];
	extractionRecord.MD5 = operation.MD5;
		
	// If trackIDs is set, the ExtractionOperation represents one or more whole tracks (and not an arbitrary range of sectors)
	// If this is the case, calculate the AccurateRip checksum(s) for the extracted tracks
	if(operation.trackIDs) {
		NSUInteger sectorOffset = 0;
		
		for(NSManagedObjectID *trackID in operation.trackIDs) {
			NSManagedObject *managedObject = [self.managedObjectContext objectRegisteredForID:trackID];
//			if(![managedObject isKindOfClass:[TrackDescriptor class]])
//				break;
			
			TrackDescriptor *track = (TrackDescriptor *)managedObject;			
			SectorRange *trackSectorRange = track.sectorRange;
			
			// Since a file may contain multiple non-sequential tracks, there is not a 1:1 correspondence between
			// LBAs on the disc and sample frame offsets in the file.  Adjust for that here
			SectorRange *adjustedSectorRange = [SectorRange sectorRangeWithFirstSector:sectorOffset sectorCount:trackSectorRange.length];
			sectorOffset += trackSectorRange.length;
			
			NSUInteger accurateRipCRC = calculateAccurateRipCRCForFileRegion(operation.URL.path, 
																			 adjustedSectorRange.firstSector,
																			 adjustedSectorRange.lastSector,
																			 self.compactDisc.firstSession.firstTrack.number.unsignedIntegerValue == track.number.unsignedIntegerValue,
																			 self.compactDisc.firstSession.lastTrack.number.unsignedIntegerValue == track.number.unsignedIntegerValue);
			
			ExtractedTrackRecord *extractedTrackRecord = [NSEntityDescription insertNewObjectForEntityForName:@"ExtractedTrackRecord" 
																					   inManagedObjectContext:self.managedObjectContext];
			
			extractedTrackRecord.track = track;
			// Since Core Data only stores signed integers, cast the unsigned CRC to signed for storage
			extractedTrackRecord.accurateRipCRC = [NSNumber numberWithInt:(int32_t)accurateRipCRC];
			
			[extractionRecord addTracksObject:extractedTrackRecord];
		}
	}
	
	// If this disc was found in Accurate Rip, verify the checksum(s) if whole tracks were extracted
	if(self.compactDisc.accurateRipDisc && operation.trackIDs) {
		BOOL allTracksWereAccuratelyExtracted = YES;

		for(NSManagedObjectID *trackID in operation.trackIDs) {
			NSManagedObject *managedObject = [self.managedObjectContext objectRegisteredForID:trackID];
//			if(![managedObject isKindOfClass:[TrackDescriptor class]])
//				break;
			
			TrackDescriptor *track = (TrackDescriptor *)managedObject;			

			AccurateRipTrackRecord *accurateRipTrack = [self.compactDisc.accurateRipDisc trackNumber:track.number.unsignedIntegerValue];
			ExtractedTrackRecord *extractedTrack = [extractionRecord trackNumber:track.number.unsignedIntegerValue];
			
			if(accurateRipTrack && accurateRipTrack.CRC.unsignedIntegerValue == extractedTrack.accurateRipCRC.unsignedIntegerValue) {
				NSLog(@"Track %@ accurately ripped, confidence %@", track.number, accurateRipTrack.confidenceLevel);
			}
			else
				allTracksWereAccuratelyExtracted = NO;
		}

		// If all tracks were accurately ripped, ship the image off to the encoder(s)
		if(allTracksWereAccuratelyExtracted) {
			
		}
	}
	// Re-rip the tracks if any C2 error flags were returned
	else if(operation.errorFlags.countOfOnes) {
		
	}
	// No C2 errors
	else {
		
	}
	
}

- (void) preGapDetectionOperationStarted:(PreGapDetectionOperation *)operation
{
	
#pragma unused(operation)
	
}

- (void) preGapDetectionOperationStopped:(PreGapDetectionOperation *)operation
{
	NSParameterAssert(nil != operation);

	if(operation.error || operation.isCancelled) {
		if(operation.error)
			[self presentError:operation.error modalForWindow:self.window delegate:nil didPresentSelector:NULL contextInfo:NULL];
		return;
	}
	
	// Refresh ourselves, to pull in the pre-gap set in the worker thread
	NSManagedObject *managedObject = [self.managedObjectContext objectRegisteredForID:operation.trackID];
	[self.managedObjectContext refreshObject:managedObject mergeChanges:YES];
}

- (void) accurateRipQueryOperationStarted:(AccurateRipQueryOperation *)operation
{

#pragma unused(operation)

}

- (void) accurateRipQueryOperationStopped:(AccurateRipQueryOperation *)operation
{
	NSParameterAssert(nil != operation);
	
	if(operation.error || operation.isCancelled) {
		if(operation.error)
			[self presentError:operation.error modalForWindow:self.window delegate:nil didPresentSelector:NULL contextInfo:NULL];
		return;
	}
	
	// Refresh ourselves, to pull in the AccurateRip data created by the worker thread
	NSManagedObject *managedObject = [self.managedObjectContext objectRegisteredForID:operation.compactDiscID];
	[self.managedObjectContext refreshObject:managedObject mergeChanges:YES];
}

- (void) musicDatabaseQueryOperationStarted:(MusicDatabaseQueryOperation *)operation
{

#pragma unused(operation)
	
}

- (void) musicDatabaseQueryOperationStopped:(MusicDatabaseQueryOperation *)operation
{
	NSParameterAssert(nil != operation);
	
	if(operation.error || operation.isCancelled) {
		if(operation.error)
			[self presentError:operation.error modalForWindow:self.window delegate:nil didPresentSelector:NULL contextInfo:NULL];
		return;
	}
	
	NSUInteger matchCount = operation.queryResults.count;
	
	if(0 == matchCount) {
		NSBeginAlertSheet(NSLocalizedStringFromTable(@"The disc was not found.", @"MusicDatabase", @""), 
						  NSLocalizedStringFromTable(@"OK", @"Buttons", @""),
						  nil, /* alternateButton */
						  nil, /* otherButton */
						  self.window, 
						  nil, /* modalDelegate */
						  NULL, /* didEndSelector */
						  NULL, /* didDismissSelector */
						  NULL, /* contextInfo */
						  NSLocalizedStringFromTable(@"No matching discs were found in the database.", @"MusicDatabase", @""));
	}
	else if(1 == matchCount)
		[self updateMetadataWithMusicDatabaseEntry:operation.queryResults.lastObject];
	else {
		MusicDatabaseMatchesSheetController *musicDatabaseMatchesSheetController = [[MusicDatabaseMatchesSheetController alloc] init];		
		musicDatabaseMatchesSheetController.matches = operation.queryResults;
		
		[[NSApplication sharedApplication] beginSheet:musicDatabaseMatchesSheetController.window 
									   modalForWindow:self.window
										modalDelegate:self 
									   didEndSelector:@selector(showMusicDatabaseMatchesSheetDidEnd:returnCode:contextInfo:) 
										  contextInfo:musicDatabaseMatchesSheetController];
	}
}

- (void) diskWasEjected
{
	[self.window performClose:nil];
}

- (void) showMusicDatabaseMatchesSheetDidEnd:(NSWindow *)sheet returnCode:(int)returnCode contextInfo:(void *)contextInfo
{
	NSParameterAssert(nil != sheet);
	NSParameterAssert(NULL != contextInfo);
	
	[sheet orderOut:self];

	MusicDatabaseMatchesSheetController *musicDatabaseMatchesSheetController = (MusicDatabaseMatchesSheetController *)contextInfo;
	
	if(NSOKButton == returnCode)
		[self updateMetadataWithMusicDatabaseEntry:musicDatabaseMatchesSheetController.selectedMatch];
}

- (void) updateMetadataWithMusicDatabaseEntry:(id)musicDatabaseEntry
{
	NSParameterAssert(nil != musicDatabaseEntry);
	
	// Set the album's metadata
	self.compactDisc.metadata.artist = [musicDatabaseEntry valueForKey:kMetadataAlbumArtistKey];
	//	self.compactDisc.metadata.composer = [musicDatabaseEntry valueForKey:kMetadataComposerKey];
	self.compactDisc.metadata.date = [musicDatabaseEntry valueForKey:kMetadataDateKey];
	self.compactDisc.metadata.discNumber = [musicDatabaseEntry valueForKey:kMetadataDiscNumberKey];
	self.compactDisc.metadata.discTotal = [musicDatabaseEntry valueForKey:kMetadataDiscTotalKey];
	self.compactDisc.metadata.genre = [musicDatabaseEntry valueForKey:kMetadataGenreKey];
	self.compactDisc.metadata.isCompilation = [musicDatabaseEntry valueForKey:kMetadataCompilationKey];
	self.compactDisc.metadata.MCN = [musicDatabaseEntry valueForKey:kMetadataMCNKey];
	self.compactDisc.metadata.musicBrainzID = [musicDatabaseEntry valueForKey:kMetadataMusicBrainzIDKey];
	self.compactDisc.metadata.title = [musicDatabaseEntry valueForKey:kMetadataAlbumTitleKey];
	
	// Fall back to album values if track values are unspecified
	NSString *artist = [musicDatabaseEntry valueForKey:kMetadataArtistKey];
	NSString *composer = [musicDatabaseEntry valueForKey:kMetadataComposerKey];
	
	// Set each track's metadata
	NSArray *trackMetadataArray = [musicDatabaseEntry valueForKey:kMusicDatabaseTracksKey];
	for(id trackMetadata in trackMetadataArray) {
		NSUInteger trackNumber = [[trackMetadata valueForKey:kMetadataTrackNumberKey] unsignedIntegerValue];
		
		TrackDescriptor *track = [self.compactDisc.firstSession trackNumber:trackNumber];
		if(!track)
			continue;
		
		NSString *trackArtist = [trackMetadata valueForKey:kMetadataArtistKey];
		track.metadata.artist = (trackArtist ? trackArtist : artist);
		
		NSString *trackComposer = [trackMetadata valueForKey:kMetadataComposerKey];
		track.metadata.composer = (trackComposer ? trackComposer : composer);
		
		track.metadata.date = [trackMetadata valueForKey:kMetadataDateKey];
		track.metadata.genre = [trackMetadata valueForKey:kMetadataGenreKey];
		track.metadata.ISRC = [musicDatabaseEntry valueForKey:kMetadataISRCKey];
		track.metadata.lyrics = [trackMetadata valueForKey:kMetadataLyricsKey];
		track.metadata.musicBrainzID = [musicDatabaseEntry valueForKey:kMetadataMusicBrainzIDKey];
		track.metadata.title = [trackMetadata valueForKey:kMetadataTitleKey];
	}
}

- (void) showStreamInformationSheetDidEnd:(NSWindow *)sheet returnCode:(int)returnCode contextInfo:(void *)contextInfo
{
	NSLog(@"showStreamInformationSheetDidEnd");
	
	[sheet orderOut:self];
}

@end
