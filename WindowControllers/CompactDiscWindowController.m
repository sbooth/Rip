/*
 *  Copyright (C) 2007 - 2008 Stephen F. Booth <me@sbooth.org>
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

#import "MusicDatabaseInterface/MusicDatabaseInterface.h"
#import "MusicDatabaseInterface/MusicDatabaseQueryOperation.h"
#import "MusicDatabaseMatchesSheetController.h"

#import "ReadMCNSheetController.h"
#import "ReadISRCsSheetController.h"
#import "DetectPregapsSheetController.h"

#import "CopyTracksSheetController.h"

#import "CDMSFFormatter.h"
#import "PregapFormatter.h"
#import "DurationFormatter.h"
#import "YesNoFormatter.h"

#import "BitArray.h"
#import "ExtractionRecord.h"
#import "ExtractedTrackRecord.h"

#import "EncoderManager.h"
#import "MusicDatabaseManager.h"

#import "FileUtilities.h"

// For getuid
#include <unistd.h>
#include <sys/types.h>

#define WINDOW_BORDER_THICKNESS ((CGFloat)20)

// ========================================
// Context objects for observeValueForKeyPath:ofObject:change:context:
// ========================================
static NSString * const kNetworkOperationQueueKVOContext		= @"org.sbooth.Rip.CompactDiscWindowController.NetworkOperationQueue.KVOContext";

@interface CompactDiscWindowController ()
@property (assign) CompactDisc * compactDisc;
@property (assign) DriveInformation * driveInformation;
@end

@interface CompactDiscWindowController (SheetCallbacks)
- (void) showMusicDatabaseMatchesSheetDidEnd:(NSWindow *)sheet returnCode:(int)returnCode contextInfo:(void *)contextInfo;
- (void) showReadMCNSheetDidEnd:(NSWindow *)sheet returnCode:(int)returnCode contextInfo:(void *)contextInfo;
- (void) showReadISRCsSheetDidEnd:(NSWindow *)sheet returnCode:(int)returnCode contextInfo:(void *)contextInfo;
- (void) showDetectPregapsSheetDidEnd:(NSWindow *)sheet returnCode:(int)returnCode contextInfo:(void *)contextInfo;
- (void) createCueSheetSavePanelDidEnd:(NSSavePanel *)sheet returnCode:(int)returnCode  contextInfo:(void *)contextInfo;
- (void) showCopyTracksSheetDidEnd:(NSWindow *)sheet returnCode:(int)returnCode contextInfo:(void *)contextInfo;
@end

@interface CompactDiscWindowController (Private)
- (void) accurateRipQueryOperationStarted:(AccurateRipQueryOperation *)operation;
- (void) accurateRipQueryOperationStopped:(AccurateRipQueryOperation *)operation;
- (void) musicDatabaseQueryOperationStarted:(MusicDatabaseQueryOperation *)operation;
- (void) musicDatabaseQueryOperationStopped:(MusicDatabaseQueryOperation *)operation;

- (BOOL) writeCueSheetToURL:(NSURL *)cueSheetURL error:(NSError **)error;
- (BOOL) writeLogFileToURL:(NSURL *)logFileURL forExtractionRecords:(NSArray *)extractionRecords error:(NSError **)error;

- (void) diskWasEjected;

- (void) updateMetadataWithMusicDatabaseEntry:(id)musicDatabaseEntry;

- (void) toggleTableColumnVisible:(id)sender;
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
@synthesize networkOperationQueue = _networkOperationQueue;

@synthesize disk = _disk;
@synthesize compactDisc = _compactDisc;
@synthesize driveInformation = _driveInformation;

- (id) init
{
	if((self = [super initWithWindowNibName:@"CompactDiscWindow"])) {
		_networkOperationQueue = [[NSOperationQueue alloc] init];

		// Observe changes in the network operations array, to be notified when each operation starts and stops
		[self.networkOperationQueue addObserver:self forKeyPath:@"operations" options:(NSKeyValueObservingOptionOld |  NSKeyValueObservingOptionNew) context:kNetworkOperationQueueKVOContext];
		
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
	NSMenu *menu = [[NSMenu alloc] initWithTitle:NSLocalizedStringFromTable(@"Track Table Columns", @"Menus", @"")];
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
	if([anItem action] == @selector(copySelectedTracks:))
		return (0 != self.compactDisc.firstSession.selectedTracks.count);
	else if([anItem action] == @selector(detectPregaps:)) {
		NSUInteger countOfSelectedTracks = self.compactDisc.firstSession.selectedTracks.count;
		
		if(1 == countOfSelectedTracks)
			[anItem setTitle:NSLocalizedStringFromTable(@"Detect Pregap", @"Menus", @"")];
		else
			[anItem setTitle:NSLocalizedStringFromTable(@"Detect Pregaps", @"Menus", @"")];

		return (0 != countOfSelectedTracks);
		
	}
	else if([anItem action] == @selector(readISRCs:)) {
		NSUInteger countOfSelectedTracks = self.compactDisc.firstSession.selectedTracks.count;
		
		if(1 == countOfSelectedTracks)
			[anItem setTitle:NSLocalizedStringFromTable(@"Read ISRC", @"Menus", @"")];
		else
			[anItem setTitle:NSLocalizedStringFromTable(@"Read ISRCs", @"Menus", @"")];
			
		return (0 != countOfSelectedTracks);
	}
	else if([anItem action] == @selector(toggleMetadataDrawer:)) {
		NSDrawerState state = [_metadataDrawer state];
		
		if(NSDrawerClosedState == state || NSDrawerClosingState == state)
			[anItem setTitle:NSLocalizedStringFromTable(@"Show Metadata", @"Menus", @"")];
		else
			[anItem setTitle:NSLocalizedStringFromTable(@"Hide Metadata", @"Menus", @"")];
		
		return YES;
	}
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
	// Network operations
	if(kNetworkOperationQueueKVOContext == context) {
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
	
	if(self.networkOperationQueue.operations.count)
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
		
		[self.networkOperationQueue cancelAllOperations];
		
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
// Copy the selected tracks to intermediate WAV files, then send to the encoder
- (IBAction) copySelectedTracks:(id)sender
{
	
#pragma unused(sender)
	
	SessionDescriptor *firstSession = self.compactDisc.firstSession;
	NSSet *selectedTracks = firstSession.selectedTracks;
	
	// Only allow one operation on the compact disc at a time
	if(0 == selectedTracks.count || [[self.networkOperationQueue operations] count]) {
		NSBeep();
		return;
	}
	
	CopyTracksSheetController *sheetController = [[CopyTracksSheetController alloc] init];
	
	sheetController.disk = self.disk;
	sheetController.trackIDs = [[selectedTracks allObjects] valueForKey:@"objectID"];
	
	[[NSApplication sharedApplication] beginSheet:sheetController.window 
								   modalForWindow:self.window
									modalDelegate:self 
								   didEndSelector:@selector(showCopyTracksSheetDidEnd:returnCode:contextInfo:) 
									  contextInfo:sheetController];
	
	[sheetController copyTracks:sender];
}

- (IBAction) copyImage:(id)sender
{

#pragma unused(sender)
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
	sheetController.trackIDs = [[selectedTracks allObjects] valueForKey:@"objectID"];
	
	[[NSApplication sharedApplication] beginSheet:sheetController.window 
								   modalForWindow:self.window
									modalDelegate:self 
								   didEndSelector:@selector(showDetectPregapsSheetDidEnd:returnCode:contextInfo:) 
									  contextInfo:sheetController];
	
	[sheetController detectPregaps:sender];
}

- (IBAction) readMCN:(id)sender
{
	ReadMCNSheetController *sheetController = [[ReadMCNSheetController alloc] init];
	
	sheetController.disk = self.disk;
	sheetController.compactDiscID = self.compactDisc.objectID;
	
	[[NSApplication sharedApplication] beginSheet:sheetController.window 
								   modalForWindow:self.window
									modalDelegate:self 
								   didEndSelector:@selector(showReadMCNSheetDidEnd:returnCode:contextInfo:) 
									  contextInfo:sheetController];
	
	[sheetController readMCN:sender];
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
	sheetController.trackIDs = [[selectedTracks allObjects] valueForKey:@"objectID"];
	
	[[NSApplication sharedApplication] beginSheet:sheetController.window 
								   modalForWindow:self.window
									modalDelegate:self 
								   didEndSelector:@selector(showReadISRCsSheetDidEnd:returnCode:contextInfo:) 
									  contextInfo:sheetController];
	
	[sheetController readISRCs:sender];
}

- (IBAction) createCueSheet:(id)sender
{

#pragma unused(sender)
	
	// Determine where to save the cue
	NSSavePanel *savePanel = [NSSavePanel savePanel];
	
	[savePanel setRequiredFileType:@"cue"];
	
	[savePanel beginSheetForDirectory:nil
								 file:self.compactDisc.metadata.title
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
	
	[self.networkOperationQueue addOperation:operation];
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
	
	MusicDatabaseMatchesSheetController *musicDatabaseMatchesSheetController = (MusicDatabaseMatchesSheetController *)contextInfo;
	
	if(NSOKButton == returnCode)
		[self updateMetadataWithMusicDatabaseEntry:musicDatabaseMatchesSheetController.selectedMatch];
}

- (void) showReadMCNSheetDidEnd:(NSWindow *)sheet returnCode:(int)returnCode contextInfo:(void *)contextInfo
{
	
#pragma unused(returnCode)
#pragma unused(contextInfo)
	
	NSParameterAssert(nil != sheet);
	
	[sheet orderOut:self];
}

- (void) showReadISRCsSheetDidEnd:(NSWindow *)sheet returnCode:(int)returnCode contextInfo:(void *)contextInfo
{
	
#pragma unused(returnCode)
#pragma unused(contextInfo)
	
	NSParameterAssert(nil != sheet);
	
	[sheet orderOut:self];
}

- (void) showDetectPregapsSheetDidEnd:(NSWindow *)sheet returnCode:(int)returnCode contextInfo:(void *)contextInfo
{
	
#pragma unused(returnCode)
#pragma unused(contextInfo)
	
	NSParameterAssert(nil != sheet);
	
	[sheet orderOut:self];
}

- (void) createCueSheetSavePanelDidEnd:(NSSavePanel *)sheet returnCode:(int)returnCode  contextInfo:(void *)contextInfo
{
	
#pragma unused(contextInfo)
	
	if(NSCancelButton == returnCode)
		return;
	
	NSURL *cueSheetURL = [sheet URL];
	
	NSError *error = nil;
	if(![self writeCueSheetToURL:cueSheetURL error:&error])
		[self presentError:error modalForWindow:self.window delegate:nil didPresentSelector:NULL contextInfo:NULL];
}

- (void) showCopyTracksSheetDidEnd:(NSWindow *)sheet returnCode:(int)returnCode contextInfo:(void *)contextInfo
{
	NSParameterAssert(nil != sheet);
	
	[sheet orderOut:self];
	
	if(NSCancelButton == returnCode)
		return;
	
	CopyTracksSheetController *sheetController = (CopyTracksSheetController *)contextInfo;
	
	// Save an extraction log file
	NSURL *logFileURL = [NSURL fileURLWithPath:[@"~/Music/Extraction.log" stringByExpandingTildeInPath]];
	
	NSError *error = nil;
	if(![self writeLogFileToURL:logFileURL forExtractionRecords:sheetController.extractionRecords error:&error])
		[self presentError:error modalForWindow:self.window delegate:nil didPresentSelector:NULL contextInfo:NULL];
}

@end

@implementation CompactDiscWindowController (Private)

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

- (BOOL) writeCueSheetToURL:(NSURL *)cueSheetURL error:(NSError **)error
{
	NSParameterAssert(nil != cueSheetURL);
	
	NSMutableString *cueSheetString = [NSMutableString string];
	
	NSString *versionNumber = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleVersion"];
	[cueSheetString appendFormat:@"REM Created by Rip %@\n", versionNumber];
	
	[cueSheetString appendString:@"\n"];

	[cueSheetString appendFormat:@"REM FreeDB Disc ID %08x\n", self.compactDisc.freeDBDiscID.integerValue];
	[cueSheetString appendFormat:@"REM MusicBrainz Disc ID %@\n", self.compactDisc.musicBrainzDiscID];

	if(self.compactDisc.metadata.date)
		[cueSheetString appendFormat:@"REM DATE %@\n", self.compactDisc.metadata.date];
	
	[cueSheetString appendString:@"\n"];
	
	if(self.compactDisc.metadata.MCN)
		[cueSheetString appendFormat:@"CATALOG %@\n", self.compactDisc.metadata.MCN];

	// Title, artist
	if(self.compactDisc.metadata.title)
		[cueSheetString appendFormat:@"TITLE \"%@\"\n", self.compactDisc.metadata.title];

	if(self.compactDisc.metadata.artist)
		[cueSheetString appendFormat:@"PERFORMER \"%@\"\n", self.compactDisc.metadata.artist];

	[cueSheetString appendString:@"\n"];
	
	for(TrackDescriptor *trackDescriptor in self.compactDisc.firstSession.orderedTracks) {
		// Track number
		[cueSheetString appendFormat:@"TRACK %02i AUDIO\n", trackDescriptor.number.integerValue];

		// Pregap
		// PREGAP uses digital silence, while INDEX 00 uses audio from the file
		// Depending on  options this should change!
		if(trackDescriptor.pregap) {
			CDMSF trackPregapMSF = CDConvertLBAToMSF(trackDescriptor.pregap.integerValue - 150);
			[cueSheetString appendFormat:@"  PREGAP %02i:%02i:%02i\n", trackPregapMSF.minute, trackPregapMSF.second, trackPregapMSF.frame];
		}
		
		// Index
		CDMSF trackMSF = CDConvertLBAToMSF(trackDescriptor.firstSector.integerValue - 150);
		[cueSheetString appendFormat:@"  INDEX 01 %02i:%02i:%02i\n", trackMSF.minute, trackMSF.second, trackMSF.frame];
		
		// Flags
		NSMutableArray *flagsArray = [NSMutableArray array];
		if(trackDescriptor.digitalCopyPermitted.boolValue)
			[flagsArray addObject:@"DCP"];
		else if(trackDescriptor.hasPreEmphasis.boolValue)
			[flagsArray addObject:@"PRE"];
		else if(4 == trackDescriptor.channelsPerFrame.integerValue)
			[flagsArray addObject:@"4CH"];
		else if(trackDescriptor.isDataTrack.boolValue)
			[flagsArray addObject:@"DATA"];

		if(flagsArray.count)
			[cueSheetString appendFormat:@"  FLAGS %@\n", [flagsArray componentsJoinedByString:@" "]];

		// ISRC
		if(trackDescriptor.metadata.ISRC)
			[cueSheetString appendFormat:@"  ISRC %@\n", trackDescriptor.metadata.ISRC];
		
		// Track title, artist and composer
		if(trackDescriptor.metadata.title)
			[cueSheetString appendFormat:@"  TITLE \"%@\"\n", trackDescriptor.metadata.title];
		
		if(trackDescriptor.metadata.artist)
			[cueSheetString appendFormat:@"  PERFORMER \"%@\"\n", trackDescriptor.metadata.artist];

		if(trackDescriptor.metadata.composer)
			[cueSheetString appendFormat:@"  SONGWRITER \"%@\"\n", trackDescriptor.metadata.composer];

		[cueSheetString appendString:@"\n"];
	}

	return [cueSheetString writeToURL:cueSheetURL atomically:YES encoding:NSUTF8StringEncoding error:error];
}


- (BOOL) writeLogFileToURL:(NSURL *)logFileURL forExtractionRecords:(NSArray *)extractionRecords error:(NSError **)error
{
	NSParameterAssert(nil != logFileURL);
	NSParameterAssert(nil != extractionRecords);
	
	// Formatters used for presenting values to the user
	CDMSFFormatter *msfFormatter = [[CDMSFFormatter alloc] init];
	PregapFormatter *pregapFormatter = [[PregapFormatter alloc] init];
	DurationFormatter *durationFormatter = [[DurationFormatter alloc] init];
	YesNoFormatter *yesNoFormatter = [[YesNoFormatter alloc] init];
	NSNumberFormatter *numberFormatter = [[NSNumberFormatter alloc] init];

	[numberFormatter setFormatterBehavior:NSNumberFormatterBehavior10_4];
	[numberFormatter setUsesGroupingSeparator:YES];
	[numberFormatter setPaddingCharacter:@" "];
	
	NSMutableString *logFileString = [NSMutableString string];
	
	// Log file header
	NSString *appName = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleName"];
	NSString *versionNumber = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleVersion"];
	[logFileString appendFormat:@"%@ %@ Audio Extraction Log\n", appName, versionNumber];
	
	[logFileString appendString:@"\n"];

	// Drive information
	[logFileString appendFormat:@"Drive used:         %@ %@", self.driveInformation.vendorName, self.driveInformation.productName];
	if(self.driveInformation.productRevisionLevel)
		[logFileString appendFormat:@" (%@)", self.driveInformation.productRevisionLevel];
	[logFileString appendString:@"\n"];
	if(self.driveInformation.productSerialNumber)
		[logFileString appendFormat:@"Serial number:      %@\n", self.driveInformation.productSerialNumber];
	[logFileString appendFormat:@"Stream accurate:    %@\n", [yesNoFormatter stringForObjectValue:self.driveInformation.hasAccurateStream]];
	[logFileString appendFormat:@"Interconnect type:  %@\n", self.driveInformation.physicalInterconnectType];
	[logFileString appendFormat:@"Location:           %@\n", self.driveInformation.physicalInterconnectLocation];
	[logFileString appendFormat:@"Read offset:        %@\n", [numberFormatter stringFromNumber:self.driveInformation.readOffset]];
	
	[logFileString appendString:@"\n"];
	
	// Disc information
	[logFileString appendString:@"Disc name:          "];
	if(self.compactDisc.metadata.artist)
		[logFileString appendString:self.compactDisc.metadata.artist];
	else
		[logFileString appendString:NSLocalizedString(@"Unknown Artist", @"")];
	[logFileString appendString:NSLocalizedString(@" - ", @"")];	
	if(self.compactDisc.metadata.title)
		[logFileString appendString:self.compactDisc.metadata.title];
	else
		[logFileString appendString:NSLocalizedString(@"Unknown Artist", @"")];
	[logFileString appendString:@"\n"];
	[logFileString appendFormat:@"FreeDB ID:          %08lx\n", self.compactDisc.freeDBDiscID.integerValue];
	[logFileString appendFormat:@"MusicBrainz ID:     %@\n", self.compactDisc.musicBrainzDiscID];
	[logFileString appendString:@"Disc TOC:\n"];
//	[logFileString appendString:@"     Track |   Start  | Duration |  Pregap  | First sector | Last sector\n"];
//	[logFileString appendString:@"    -------+----------+----------+----------+--------------+-------------\n"];
	[logFileString appendString:@"     Track |   Start  | Duration | First sector | Last sector\n"];
	[logFileString appendString:@"    -------+----------+----------+--------------+-------------\n"];
		
	for(TrackDescriptor *trackDescriptor in self.compactDisc.firstSession.orderedTracks) {
		// Track number
		[logFileString appendString:@"       "];
		[numberFormatter setFormatWidth:2];
		[logFileString appendString:[numberFormatter stringFromNumber:trackDescriptor.number]];
		[logFileString appendString:@"  | "];

		// Start sector and duration
		[logFileString appendString:[msfFormatter stringForObjectValue:[NSNumber numberWithUnsignedInteger:(trackDescriptor.firstSector.unsignedIntegerValue - 150)]]];
		[logFileString appendString:@" | "];
		[logFileString appendString:[msfFormatter stringForObjectValue:[NSNumber numberWithUnsignedInteger:(trackDescriptor.sectorCount - 150)]]];
		[logFileString appendString:@" | "];

		// Pregap
//		if(trackDescriptor.pregap)
//			[logFileString appendString:[pregapFormatter stringForObjectValue:trackDescriptor.pregap]];
//		else
//			[logFileString appendString:@"        "];
//		[logFileString appendString:@" | "];
		
		// First and last sector number
		[numberFormatter setFormatWidth:10];
		[logFileString appendString:[numberFormatter stringFromNumber:trackDescriptor.firstSector]];
		[logFileString appendString:@"   |   "];
		[numberFormatter setFormatWidth:7];
		[logFileString appendString:[numberFormatter stringFromNumber:trackDescriptor.lastSector]];		
		[logFileString appendString:@"\n"];
	}

	[logFileString appendString:@"\n"];
	
	[numberFormatter setFormatWidth:0];

	for(ExtractionRecord *extractionRecord in extractionRecords) {
		if(1 == [extractionRecord.orderedTracks count]) {
			ExtractedTrackRecord *extractedTrackRecord = [extractionRecord.orderedTracks lastObject];
			
			[logFileString appendFormat:@"Track %@ saved to %@\n", extractedTrackRecord.track.number, [extractionRecord.URL path]];
			
			if([extractionRecord.errorFlags countOfOnes])
				[logFileString appendFormat:@"    C2 error count:         %@\n", [numberFormatter stringForObjectValue:[NSNumber numberWithUnsignedInteger:[extractionRecord.errorFlags countOfOnes]]]];
			[logFileString appendFormat:@"    AccurateRip checksum:   %lx\n", extractedTrackRecord.accurateRipChecksum.unsignedIntegerValue];
			[logFileString appendFormat:@"    Audio MD5 hash:         %@\n", extractionRecord.MD5];
			[logFileString appendFormat:@"    Audio SHA1 hash:        %@\n", extractionRecord.SHA1];
		}
		else {
			NSLog(@"FIXME: LOG FILE FOR IMAGE EXTRACTION");
		}
	}
	
	return [logFileString writeToURL:logFileURL atomically:YES encoding:NSUTF8StringEncoding error:error];
}

@end
