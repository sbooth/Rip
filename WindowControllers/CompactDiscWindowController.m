/*
 *  Copyright (C) 2007 - 2008 Stephen F. Booth <me@sbooth.org>
 *  All Rights Reserved
 */

#import "CompactDiscWindowController.h"
#import "CompactDiscWindowController+LogFileGeneration.h"

#import "CompactDisc.h"
#import "CompactDisc+CueSheetGeneration.h"
#import "SessionDescriptor.h"
#import "TrackDescriptor.h"
#import "AlbumMetadata.h"
#import "TrackMetadata.h"

#import "AccurateRipQueryOperation.h"

#import "DriveInformation.h"

#import "MusicDatabaseInterface/MusicDatabaseInterface.h"
#import "MusicDatabaseInterface/MusicDatabaseQueryOperation.h"
#import "MusicDatabaseMatchesSheetController.h"

#import "ReadOffsetCalculatorSheetController.h"
#import "ReadMCNSheetController.h"
#import "ReadISRCsSheetController.h"
#import "DetectPregapsSheetController.h"

#import "AudioExtractionSheetController.h"

#import "EncoderManager.h"
#import "MusicDatabaseManager.h"

#import "FileUtilities.h"
#import "AccurateRipDiscRecord.h"
#import "AccurateRipTrackRecord.h"

#define WINDOW_BORDER_THICKNESS ((CGFloat)20)

// ========================================
// Context objects for observeValueForKeyPath:ofObject:change:context:
// ========================================
static NSString * const kOperationQueueKVOContext		= @"org.sbooth.Rip.CompactDiscWindowController.KVOContext";
static NSString * const kAccurateRipQueryKVOContext		= @"org.sbooth.Rip.CompactDiscWindowController.AccurateRipQueryKVOContext";
static NSString * const kMusicDatabaseQueryKVOContext	= @"org.sbooth.Rip.CompactDiscWindowController.MusicDatabaseQueryKVOContext";

@interface CompactDiscWindowController ()
@property (assign) CompactDisc * compactDisc;
@property (assign) DriveInformation * driveInformation;

@property (readonly) NSOperationQueue * operationQueue;
@property (assign) int extractionMode;

@property (readonly) NSManagedObjectContext * managedObjectContext;
@property (readonly) id managedObjectModel;
@end

@interface CompactDiscWindowController (SheetCallbacks)
- (void) showMusicDatabaseMatchesSheetDidEnd:(NSWindow *)sheet returnCode:(int)returnCode contextInfo:(void *)contextInfo;
- (void) createCueSheetSavePanelDidEnd:(NSSavePanel *)sheet returnCode:(int)returnCode  contextInfo:(void *)contextInfo;
- (void) showReadMCNSheetDidEnd:(NSWindow *)sheet returnCode:(int)returnCode contextInfo:(void *)contextInfo;
- (void) showReadISRCsSheetDidEnd:(NSWindow *)sheet returnCode:(int)returnCode contextInfo:(void *)contextInfo;
- (void) showDetectPregapsSheetDidEnd:(NSWindow *)sheet returnCode:(int)returnCode contextInfo:(void *)contextInfo;
- (void) showCopyTracksSheetDidEnd:(NSWindow *)sheet returnCode:(int)returnCode contextInfo:(void *)contextInfo;
- (void) showCopyImageSheetDidEnd:(NSWindow *)sheet returnCode:(int)returnCode contextInfo:(void *)contextInfo;
@end

@interface CompactDiscWindowController (Private)
- (void) beginReadMCNSheet;
- (void) beginReadISRCsSheet;
- (void) beginDetectPregapsSheet;
- (void) performShowCopyTracksSheet;
- (void) performShowCopyImageSheet;

- (void) diskWasEjected;

- (void) updateMetadataWithMusicDatabaseEntry:(id)musicDatabaseEntry;

- (void) toggleTableColumnVisible:(id)sender;

- (void) accurateRipQueryOperationDidReturn:(AccurateRipQueryOperation *)operation;
- (void) musicDatabaseQueryOperationDidReturn:(MusicDatabaseQueryOperation *)operation;
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

@synthesize trackController = _trackController;
@synthesize driveInformationController = _driveInformationController;
@synthesize operationQueue = _operationQueue;
@synthesize extractionMode = _extractionMode;

@synthesize disk = _disk;
@synthesize compactDisc = _compactDisc;
@synthesize driveInformation = _driveInformation;

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

- (void) awakeFromNib
{
	// Our window has a bottom border used to display the AccurateRip availability for this disc and total playing time
	[self.window setAutorecalculatesContentBorderThickness:YES forEdge:NSMinYEdge];
	[self.window setContentBorderThickness:WINDOW_BORDER_THICKNESS forEdge:NSMinYEdge];
	
	// Create the menu for the table's header, to allow showing and hiding of columns
	NSMenu *menu = [[NSMenu alloc] initWithTitle:NSLocalizedString(@"Track Table Columns", @"")];
	NSSortDescriptor *tableColumnsNameSortDescriptor = [[NSSortDescriptor alloc] initWithKey:@"headerCell.title" ascending:YES];
	NSArray *sortedTableColumns = [_trackTable.tableColumns sortedArrayUsingDescriptors:[NSArray arrayWithObject:tableColumnsNameSortDescriptor]];
	for(NSTableColumn *column in sortedTableColumns) {
		NSMenuItem *menuItem = [menu addItemWithTitle:[column.headerCell title]
											   action:@selector(toggleTableColumnVisible:) 
										keyEquivalent:@""];
		[menuItem setTarget:self];
		[menuItem setRepresentedObject:column];
		[menuItem setState:!column.isHidden];
	}
	[_trackTable.headerView setMenu:menu];
	
	// Set the default sort descriptors for the track table
	NSSortDescriptor *trackNumberSortDescriptor = [[NSSortDescriptor alloc] initWithKey:@"number" ascending:YES];
	[self.trackController setSortDescriptors:[NSArray arrayWithObject:trackNumberSortDescriptor]];	
}

- (BOOL) validateMenuItem:(NSMenuItem *)anItem
{
	if([anItem action] == @selector(copySelectedTracks:)) {
		NSUInteger countOfSelectedTracks = self.compactDisc.firstSession.selectedTracks.count;
		
		if(1 == countOfSelectedTracks)
			[anItem setTitle:NSLocalizedString(@"Copy Track", @"")];
		else
			[anItem setTitle:NSLocalizedString(@"Copy Tracks", @"")];
		
		return (0 != countOfSelectedTracks);
	}
	else if([anItem action] == @selector(detectPregaps:)) {
		NSUInteger countOfSelectedTracks = self.compactDisc.firstSession.selectedTracks.count;
		
		if(1 == countOfSelectedTracks)
			[anItem setTitle:NSLocalizedString(@"Detect Pregap", @"")];
		else
			[anItem setTitle:NSLocalizedString(@"Detect Pregaps", @"")];

		return (0 != countOfSelectedTracks);		
	}
	else if([anItem action] == @selector(readISRCs:)) {
		NSUInteger countOfSelectedTracks = self.compactDisc.firstSession.selectedTracks.count;
		
		if(1 == countOfSelectedTracks)
			[anItem setTitle:NSLocalizedString(@"Read ISRC", @"")];
		else
			[anItem setTitle:NSLocalizedString(@"Read ISRCs", @"")];
			
		return (0 != countOfSelectedTracks);
	}
	else if([anItem action] == @selector(toggleMetadataDrawer:)) {
		NSDrawerState state = [_metadataDrawer state];
		
		if(NSDrawerClosedState == state || NSDrawerClosingState == state)
			[anItem setTitle:NSLocalizedString(@"Show Metadata", @"")];
		else
			[anItem setTitle:NSLocalizedString(@"Hide Metadata", @"")];
		
		return YES;
	}
//	else if([anItem action] == @selector(determineDriveReadOffset:)) {
//		if(self.driveInformation.productName)
//			[anItem setTitle:[NSString stringWithFormat:NSLocalizedString(@"Determine Read Offset for \u201c%@ %@\u201d", @""), self.driveInformation.vendorName, self.driveInformation.productName]];
//		else
//			[anItem setTitle:NSLocalizedString(@"Determine Read Offset", @"")];
//			
//		return YES;
//	}
	else if([self respondsToSelector:[anItem action]])
		return YES;
	else
		return NO;
}

- (BOOL) validateToolbarItem:(NSToolbarItem *)theItem
{
	if([theItem action] == @selector(copySelectedTracks:))
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

#pragma mark NSTableView Delegate Methods

- (void) tableView:(NSTableView *)aTableView willDisplayCell:(id)aCell forTableColumn:(NSTableColumn *)aTableColumn row:(NSInteger)rowIndex
{

#pragma unused(aTableView)

	if([aTableColumn.identifier isEqualToString:@"isSelected"])
		[aCell setTitle:[[[_trackController.arrangedObjects objectAtIndex:rowIndex] valueForKey:@"number"] stringValue]];
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

- (IBAction) toggleMetadataDrawer:(id)sender
{
	[_metadataDrawer toggle:sender];	
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
	
	self.extractionMode = eExtractionModeIndividualTracks;
	
	// Start the sheet cascade
	[self beginReadMCNSheet];
}

- (IBAction) copyImage:(id)sender
{

#pragma unused(sender)

	self.extractionMode = eExtractionModeImage;
	
	// Start the sheet cascade
	[self beginReadMCNSheet];
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
								 file:makeStringSafeForFilename(self.compactDisc.metadata.title)
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
	operation.settings = musicDatabaseSettings;
	operation.discTOC = self.compactDisc.discTOC;
	operation.freeDBDiscID = self.compactDisc.freeDBDiscID;
	operation.musicBrainzDiscID = self.compactDisc.musicBrainzDiscID;
	
	[self.operationQueue addOperation:operation];	
}

- (IBAction) queryAccurateRip:(id)sender
{

#pragma unused(sender)

	AccurateRipQueryOperation *operation = [[AccurateRipQueryOperation alloc] init];
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

- (void) showReadMCNSheetDidEnd:(NSWindow *)sheet returnCode:(int)returnCode contextInfo:(void *)contextInfo
{
	NSParameterAssert(nil != sheet);
	
	[sheet orderOut:self];
	
	ReadMCNSheetController *sheetController = (ReadMCNSheetController *)contextInfo;
	sheetController = nil;
	
	if(NSCancelButton == returnCode)
		return;
	
	[self beginReadISRCsSheet];
}

- (void) showReadISRCsSheetDidEnd:(NSWindow *)sheet returnCode:(int)returnCode contextInfo:(void *)contextInfo
{
	NSParameterAssert(nil != sheet);
	
	[sheet orderOut:self];
	
	ReadISRCsSheetController *sheetController = (ReadISRCsSheetController *)contextInfo;
	sheetController = nil;
	
	if(NSCancelButton == returnCode)
		return;
	
	[self beginDetectPregapsSheet];
}

- (void) showDetectPregapsSheetDidEnd:(NSWindow *)sheet returnCode:(int)returnCode contextInfo:(void *)contextInfo
{
	NSParameterAssert(nil != sheet);
	
	[sheet orderOut:self];
	
	DetectPregapsSheetController *sheetController = (DetectPregapsSheetController *)contextInfo;
	sheetController = nil;
	
	if(NSCancelButton == returnCode)
		return;
	
	if(eExtractionModeImage == self.extractionMode)
		[self performShowCopyImageSheet];
	else if(eExtractionModeIndividualTracks == self.extractionMode)
		[self performShowCopyTracksSheet];
}

- (void) showCopyTracksSheetDidEnd:(NSWindow *)sheet returnCode:(int)returnCode contextInfo:(void *)contextInfo
{
	NSParameterAssert(nil != sheet);
	
	[sheet orderOut:self];
	
	if(NSCancelButton == returnCode)
		return;
	
	AudioExtractionSheetController *sheetController = (AudioExtractionSheetController *)contextInfo;
	
	// Alert the user if any tracks failed to extract
	if([sheetController.failedTrackIDs count]) {
		// Fetch the tracks that failed and sort them by track number
		NSPredicate *trackPredicate  = [NSPredicate predicateWithFormat:@"self IN %@", sheetController.failedTrackIDs];
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
		NSBeginCriticalAlertSheet([NSString stringWithFormat:NSLocalizedString(@"Some tracks from \u201c%@\u201d could not be copied because read errors occurred during audio extraction.", @""), albumTitle],
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
	
	// Save an extraction log file if any tracks were successfully extracted
	if(![sheetController.trackExtractionRecords count])
		return;
	
	NSString *title = self.compactDisc.metadata.title;
	if(nil == title)
		title = NSLocalizedString(@"Unknown Album", @"");
	
	NSURL *baseURL = [[EncoderManager sharedEncoderManager] outputURLForCompactDisc:self.compactDisc];
	NSString *filename = makeStringSafeForFilename(title);
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
	if(![self writeLogFileToURL:logFileURL forTrackExtractionRecords:sheetController.trackExtractionRecords error:&error])
		[self presentError:error modalForWindow:self.window delegate:nil didPresentSelector:NULL contextInfo:NULL];
	
	// Save a cue sheet
}

- (void) showCopyImageSheetDidEnd:(NSWindow *)sheet returnCode:(int)returnCode contextInfo:(void *)contextInfo
{
	NSParameterAssert(nil != sheet);
	
	[sheet orderOut:self];
	
	if(NSCancelButton == returnCode)
		return;
	
	AudioExtractionSheetController *sheetController = (AudioExtractionSheetController *)contextInfo;
	
	// Alert the user if any tracks failed to extract
	if([sheetController.failedTrackIDs count]) {
		// Fetch the tracks that failed and sort them by track number
		NSPredicate *trackPredicate  = [NSPredicate predicateWithFormat:@"self IN %@", sheetController.failedTrackIDs];
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
		NSBeginCriticalAlertSheet([NSString stringWithFormat:NSLocalizedString(@"The image of \u201c%@\u201d could not be created because read errors occurred during audio extraction.", @""), albumTitle],
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
	
		return;
	}

	// Save an extraction log file if any tracks were successfully extracted
	if(!sheetController.imageExtractionRecord)
		return;
	
	NSString *title = self.compactDisc.metadata.title;
	if(nil == title)
		title = NSLocalizedString(@"Unknown Album", @"");
	
	NSURL *baseURL = [[EncoderManager sharedEncoderManager] outputURLForCompactDisc:self.compactDisc];
	NSString *filename = makeStringSafeForFilename(title);
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
	if(![self writeLogFileToURL:logFileURL forImageExtractionRecord:sheetController.imageExtractionRecord error:&error])
		[self presentError:error modalForWindow:self.window delegate:nil didPresentSelector:NULL contextInfo:NULL];
	
	// Save a cue sheet
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

	// Set the album's metadata
	self.compactDisc.metadata.artist = [musicDatabaseEntry valueForKey:kMetadataAlbumArtistKey];
	self.compactDisc.metadata.date = [musicDatabaseEntry valueForKey:kMetadataReleaseDateKey];
	self.compactDisc.metadata.discNumber = [musicDatabaseEntry valueForKey:kMetadataDiscNumberKey];
	self.compactDisc.metadata.discTotal = [musicDatabaseEntry valueForKey:kMetadataDiscTotalKey];
	self.compactDisc.metadata.isCompilation = [musicDatabaseEntry valueForKey:kMetadataCompilationKey];
	self.compactDisc.metadata.MCN = [musicDatabaseEntry valueForKey:kMetadataMCNKey];
	self.compactDisc.metadata.musicBrainzID = [musicDatabaseEntry valueForKey:kMetadataMusicBrainzIDKey];
	self.compactDisc.metadata.title = [musicDatabaseEntry valueForKey:kMetadataAlbumTitleKey];

	// Set each track's metadata
	NSArray *trackMetadataArray = [musicDatabaseEntry valueForKey:kMusicDatabaseTracksKey];
	for(id trackMetadata in trackMetadataArray) {
		NSUInteger trackNumber = [[trackMetadata valueForKey:kMetadataTrackNumberKey] unsignedIntegerValue];
		
		TrackDescriptor *track = [self.compactDisc.firstSession trackNumber:trackNumber];
		if(!track)
			continue;
		
		track.metadata.artist = [trackMetadata valueForKey:kMetadataArtistKey];
		track.metadata.composer = [trackMetadata valueForKey:kMetadataComposerKey];
		track.metadata.date = [trackMetadata valueForKey:kMetadataReleaseDateKey];
		track.metadata.genre = [trackMetadata valueForKey:kMetadataGenreKey];
		track.metadata.ISRC = [musicDatabaseEntry valueForKey:kMetadataISRCKey];
		track.metadata.lyrics = [trackMetadata valueForKey:kMetadataLyricsKey];
		track.metadata.musicBrainzID = [musicDatabaseEntry valueForKey:kMetadataMusicBrainzIDKey];
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

- (void) beginReadMCNSheet
{
	// Read the MCN for the disc, if not present
	if(!self.compactDisc.metadata.MCN) {
		ReadMCNSheetController *sheetController = [[ReadMCNSheetController alloc] init];
		
		sheetController.disk = self.disk;
		
		[sheetController beginReadMCNSheetForWindow:self.window
									  modalDelegate:self 
									 didEndSelector:@selector(showReadMCNSheetDidEnd:returnCode:contextInfo:) 
										contextInfo:sheetController];
	}
	else
		[self beginReadISRCsSheet];
}

- (void) beginReadISRCsSheet
{
	NSArray *tracksToIterate = nil;
	if(eExtractionModeIndividualTracks == self.extractionMode)
		tracksToIterate = self.compactDisc.firstSession.orderedSelectedTracks;
	else if(eExtractionModeImage == self.extractionMode)
		tracksToIterate = self.compactDisc.firstSession.orderedTracks;

	NSMutableArray *tracksWithoutISRCs = [NSMutableArray array];
	
	// Ensure ISRCs have been read for the desired tracks
	for(TrackDescriptor *track in tracksToIterate) {
		// Don't waste time re-reading a pre-existing ISRC
		if(!track.metadata.ISRC)
			[tracksWithoutISRCs addObject:track];
	}
	
	if([tracksWithoutISRCs count]) {
		ReadISRCsSheetController *sheetController = [[ReadISRCsSheetController alloc] init];
		
		sheetController.disk = self.disk;
		sheetController.trackIDs = [tracksWithoutISRCs valueForKey:@"objectID"];
		
		[sheetController beginReadISRCsSheetForWindow:self.window
										modalDelegate:self 
									   didEndSelector:@selector(showReadISRCsSheetDidEnd:returnCode:contextInfo:) 
										  contextInfo:sheetController];
	}
	else
		[self beginDetectPregapsSheet];
}

- (void) beginDetectPregapsSheet
{
	NSArray *tracksToIterate = nil;
	if(eExtractionModeIndividualTracks == self.extractionMode)
		tracksToIterate = self.compactDisc.firstSession.orderedSelectedTracks;
	else if(eExtractionModeImage == self.extractionMode)
		tracksToIterate = self.compactDisc.firstSession.orderedTracks;

	NSMutableArray *tracksWithoutPregaps = [NSMutableArray array];
	
	// Ensure pregaps have been read for the desired tracks
	for(TrackDescriptor *track in tracksToIterate) {
		// Grab pre-gaps
		if(!track.pregap)
			[tracksWithoutPregaps addObject:track];
	}
	
	if([tracksWithoutPregaps count]) {
		DetectPregapsSheetController *sheetController = [[DetectPregapsSheetController alloc] init];
		
		sheetController.disk = self.disk;
		sheetController.trackIDs = [tracksWithoutPregaps valueForKey:@"objectID"];
		
		[sheetController beginDetectPregapsSheetForWindow:self.window
											modalDelegate:self 
										   didEndSelector:@selector(showDetectPregapsSheetDidEnd:returnCode:contextInfo:) 
											  contextInfo:sheetController];
	}
	else {
		if(eExtractionModeImage == self.extractionMode)
			[self performShowCopyImageSheet];
		else if(eExtractionModeIndividualTracks == self.extractionMode)
			[self performShowCopyTracksSheet];
	}
}

- (void) performShowCopyTracksSheet
{
	NSSet *selectedTracks = self.compactDisc.firstSession.selectedTracks;

	AudioExtractionSheetController *sheetController = [[AudioExtractionSheetController alloc] init];
	
	sheetController.disk = self.disk;
	sheetController.extractionMode = eExtractionModeIndividualTracks;
	sheetController.trackIDs = [selectedTracks valueForKey:@"objectID"];
	
	sheetController.maxRetries = [[NSUserDefaults standardUserDefaults] integerForKey:@"maxRetries"];
	sheetController.requiredMatches = [[NSUserDefaults standardUserDefaults] integerForKey:@"requiredMatches"];
	
	[sheetController beginAudioExtractionSheetForWindow:self.window
										  modalDelegate:self 
										 didEndSelector:@selector(showCopyTracksSheetDidEnd:returnCode:contextInfo:) 
											contextInfo:sheetController];
}

- (void) performShowCopyImageSheet
{
	AudioExtractionSheetController *sheetController = [[AudioExtractionSheetController alloc] init];
	
	sheetController.disk = self.disk;
	sheetController.extractionMode = eExtractionModeImage;
	sheetController.trackIDs = [self.compactDisc.firstSession.tracks valueForKey:@"objectID"];
	
	sheetController.maxRetries = [[NSUserDefaults standardUserDefaults] integerForKey:@"maxRetries"];
	sheetController.requiredMatches = [[NSUserDefaults standardUserDefaults] integerForKey:@"requiredMatches"];
	
	[sheetController beginAudioExtractionSheetForWindow:self.window
										  modalDelegate:self 
										 didEndSelector:@selector(showCopyImageSheetDidEnd:returnCode:contextInfo:) 
											contextInfo:sheetController];
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

@end
