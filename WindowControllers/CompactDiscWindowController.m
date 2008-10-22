/*
 *  Copyright (C) 2007 - 2008 Stephen F. Booth <me@sbooth.org>
 *  All Rights Reserved
 */

#import "CompactDiscWindowController.h"
#import "CompactDiscWindowController+LogFileGeneration.h"

#import "CompactDisc.h"
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

#import "CopyTracksSheetController.h"

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

@property (readonly) NSManagedObjectContext * managedObjectContext;
@property (readonly) id managedObjectModel;
@end

@interface CompactDiscWindowController (SheetCallbacks)
- (void) showMusicDatabaseMatchesSheetDidEnd:(NSWindow *)sheet returnCode:(int)returnCode contextInfo:(void *)contextInfo;
- (void) createCueSheetSavePanelDidEnd:(NSSavePanel *)sheet returnCode:(int)returnCode  contextInfo:(void *)contextInfo;
- (void) showCopyTracksSheetDidEnd:(NSWindow *)sheet returnCode:(int)returnCode contextInfo:(void *)contextInfo;
@end

@interface CompactDiscWindowController (Private)
- (BOOL) writeCueSheetToURL:(NSURL *)cueSheetURL error:(NSError **)error;

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
@synthesize operationQueue = _operationQueue;

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
	else if([anItem action] == @selector(determineDriveReadOffset:)) {
		if(self.driveInformation.productName)
			[anItem setTitle:[NSString stringWithFormat:NSLocalizedString(@"Determine Read Offset for \u201c%@ %@\u201d", @""), self.driveInformation.vendorName, self.driveInformation.productName]];
		else
			[anItem setTitle:NSLocalizedString(@"Determine Read Offset", @"")];
			
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
	if(kAccurateRipQueryKVOContext == context) {
		AccurateRipQueryOperation *operation = (AccurateRipQueryOperation *)object;
		
		if([keyPath isEqualToString:@"isExecuting"]) {
			if([operation isExecuting]) {
			}
		}
		else if([keyPath isEqualToString:@"isCancelled"] || [keyPath isEqualToString:@"isFinished"]) {
			[operation removeObserver:self forKeyPath:@"isExecuting"];
			[operation removeObserver:self forKeyPath:@"isCancelled"];
			[operation removeObserver:self forKeyPath:@"isFinished"];

			if(operation.error)
				[self presentError:operation.error modalForWindow:self.window delegate:nil didPresentSelector:NULL contextInfo:NULL];
		}
	}
	else if(kMusicDatabaseQueryKVOContext == context) {
		MusicDatabaseQueryOperation *operation = (MusicDatabaseQueryOperation *)object;
		
		if([keyPath isEqualToString:@"isExecuting"]) {
			if([operation isExecuting]) {
			}
		}
		else if([keyPath isEqualToString:@"isCancelled"] || [keyPath isEqualToString:@"isFinished"]) {
			[operation removeObserver:self forKeyPath:@"isExecuting"];
			[operation removeObserver:self forKeyPath:@"isCancelled"];
			[operation removeObserver:self forKeyPath:@"isFinished"];
			
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
	
	CopyTracksSheetController *sheetController = [[CopyTracksSheetController alloc] init];
	
	sheetController.disk = self.disk;
	sheetController.trackIDs = [selectedTracks valueForKey:@"objectID"];
	
	[sheetController beginCopyTracksSheetForWindow:self.window
									 modalDelegate:self 
									didEndSelector:@selector(showCopyTracksSheetDidEnd:returnCode:contextInfo:) 
									   contextInfo:sheetController];
}

- (IBAction) copyImage:(id)sender
{

#pragma unused(sender)
	
	for(AccurateRipDiscRecord *arDisc in self.compactDisc.accurateRipDiscs) {
		NSLog(@"%@",arDisc);
		for(AccurateRipTrackRecord *arTrack in arDisc.tracks) {
			NSLog(@"Track %@ [%@]",arTrack.number, arTrack.confidenceLevel);
		}
		NSLog(@"\n");			
	}
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

- (BOOL) writeCueSheetToURL:(NSURL *)cueSheetURL error:(NSError **)error
{
	NSParameterAssert(nil != cueSheetURL);
	
	NSMutableString *cueSheetString = [NSMutableString string];
	
	NSString *appName = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleName"];
	NSString *shortVersionNumber = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleShortVersionString"];
	NSString *versionNumber = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleVersion"];	
	[cueSheetString appendFormat:@"REM Created by %@ %@ (%@)\n", appName, shortVersionNumber, versionNumber];
	
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
		if(trackDescriptor.hasPreEmphasis.boolValue)
			[flagsArray addObject:@"PRE"];
		if(4 == trackDescriptor.channelsPerFrame.integerValue)
			[flagsArray addObject:@"4CH"];
		if(trackDescriptor.isDataTrack.boolValue)
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

@end
