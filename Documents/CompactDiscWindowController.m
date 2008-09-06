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

#import "BitArray.h"
#import "SectorRange.h"
#import "ExtractionOperation.h"
#import "ExtractionRecord.h"
#import "ExtractedTrackRecord.h"

#import "PreGapDetectionOperation.h"

#import "MCNDetectionOperation.h"
#import "ISRCDetectionOperation.h"

#import "MusicDatabaseInterface/MusicDatabaseInterface.h"
#import "MusicDatabaseInterface/MusicDatabaseQueryOperation.h"
#import "MusicDatabaseMatchesSheetController.h"

#import "CopyTracksSheetController.h"
#import "TagEditingSheetController.h"

#import "EncoderManager.h"
#import "MusicDatabaseManager.h"

#import "KBPopUpToolbarItem.h"

// For getuid
#include <unistd.h>
#include <sys/types.h>

#define WINDOW_BORDER_THICKNESS ((CGFloat)20)

// ========================================
// Context objects for observeValueForKeyPath:ofObject:change:context:
// ========================================
NSString * const	kCompactDiscOperationQueueKVOContext	= @"org.sbooth.Rip.CompactDiscWindowController.CompactDiscOperationQueue.KVOContext";
NSString * const	kNetworkOperationQueueKVOContext		= @"org.sbooth.Rip.CompactDiscWindowController.NetworkOperationQueue.KVOContext";

@interface CompactDiscWindowController ()
@property (assign) CompactDisc * compactDisc;
@property (assign) DriveInformation * driveInformation;
@property (assign) NSSet * tracksToBeExtracted;
@property (assign) NSSet * tracksAccuratelyExtracted;
@end

@interface CompactDiscWindowController (Private)
- (void) extractionOperationStarted:(ExtractionOperation *)operation;
- (void) extractionOperationStopped:(ExtractionOperation *)operation;
- (void) preGapDetectionOperationStarted:(PreGapDetectionOperation *)operation;
- (void) preGapDetectionOperationStopped:(PreGapDetectionOperation *)operation;
- (void) MCNDetectionOperationStarted:(MCNDetectionOperation *)operation;
- (void) MCNDetectionOperationStopped:(MCNDetectionOperation *)operation;
- (void) ISRCDetectionOperationStarted:(ISRCDetectionOperation *)operation;
- (void) ISRCDetectionOperationStopped:(ISRCDetectionOperation *)operation;
- (void) accurateRipQueryOperationStarted:(AccurateRipQueryOperation *)operation;
- (void) accurateRipQueryOperationStopped:(AccurateRipQueryOperation *)operation;
- (void) musicDatabaseQueryOperationStarted:(MusicDatabaseQueryOperation *)operation;
- (void) musicDatabaseQueryOperationStopped:(MusicDatabaseQueryOperation *)operation;

- (void) diskWasEjected;

- (void) showMusicDatabaseMatchesSheetDidEnd:(NSWindow *)sheet returnCode:(int)returnCode contextInfo:(void *)contextInfo;
- (void) updateMetadataWithMusicDatabaseEntry:(id)musicDatabaseEntry;

- (void) toggleTableColumnVisible:(id)sender;
- (ExtractionRecord *) createExtractionRecordForOperation:(ExtractionOperation *)operation checksums:(NSDictionary *)checksums;

- (void) showCopyTracksSheetDidEnd:(NSWindow *)sheet returnCode:(int)returnCode contextInfo:(void *)contextInfo;
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

@synthesize tracksToBeExtracted = _tracksToBeExtracted;
@synthesize tracksAccuratelyExtracted = _tracksAccuratelyExtracted;

- (id) init
{
	if((self = [super initWithWindowNibName:@"CompactDiscWindow"])) {
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
	
	// Create the menu for the table's header, to allow showing and hiding of columns
	NSMenu *menu = [[NSMenu alloc] initWithTitle:NSLocalizedStringFromTable(@"Track Table Columns", @"", @"")];
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

#if 0
	NSArray *tracks = [self.trackController arrangedObjects];
	for(TrackDescriptor *track in tracks) {
		NSLog(@"Pregap for track %@: %@", track.number, track.preGap);
	}
#endif
	
}

- (BOOL) validateUserInterfaceItem:(id <NSValidatedUserInterfaceItem>)anItem
{
	if([anItem action] == @selector(copySelectedTracks:))
		return (0 != self.compactDisc.firstSession.selectedTracks.count && 0 == self.compactDiscOperationQueue.operations.count);
	else if([anItem action] == @selector(copyImage:))
		return (0 == self.compactDiscOperationQueue.operations.count);
	else if([anItem action] == @selector(queryDefaultMusicDatabase:))
		return YES;
	else if([anItem action] == @selector(queryFreeDB:))
		return YES;
	else if([anItem action] == @selector(queryMusicBrainz:))
		return YES;
	else if([anItem action] == @selector(queryiTunes:))
		return (nil != [[NSWorkspace sharedWorkspace] absolutePathForAppBundleWithIdentifier:@"com.apple.iTunes"]);
	else if([anItem action] == @selector(queryAccurateRip:))
		return YES;
	else if([anItem action] == @selector(detectPreGaps:))
		return (0 != self.compactDisc.firstSession.selectedTracks.count && 0 == self.compactDiscOperationQueue.operations.count);
	else if([anItem action] == @selector(readMCN:))
		return (0 == self.compactDiscOperationQueue.operations.count);
	else if([anItem action] == @selector(readISRCs:))
		return (0 != self.compactDisc.firstSession.selectedTracks.count && 0 == self.compactDiscOperationQueue.operations.count);
	else if([anItem action] == @selector(toggleTableColumnVisible:))
		return YES;
	else if([anItem action] == @selector(editTags:))
		return YES;
	else if([self respondsToSelector:[anItem action]])
		return YES;
	else
		return NO;
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
				else if([operation isKindOfClass:[MCNDetectionOperation class]])
					[self MCNDetectionOperationStarted:(MCNDetectionOperation *)operation];
				else if([operation isKindOfClass:[ISRCDetectionOperation class]])
					[self ISRCDetectionOperationStarted:(ISRCDetectionOperation *)operation];
			}
		}
		else if(NSKeyValueChangeRemoval == changeKind) {
			for(NSOperation *operation in [change objectForKey:NSKeyValueChangeOldKey])
				if([operation isKindOfClass:[ExtractionOperation class]])
					[self extractionOperationStopped:(ExtractionOperation *)operation];
				else if([operation isKindOfClass:[PreGapDetectionOperation class]])
					[self preGapDetectionOperationStopped:(PreGapDetectionOperation *)operation];
				else if([operation isKindOfClass:[MCNDetectionOperation class]])
					[self MCNDetectionOperationStopped:(MCNDetectionOperation *)operation];
				else if([operation isKindOfClass:[ISRCDetectionOperation class]])
					[self ISRCDetectionOperationStopped:(ISRCDetectionOperation *)operation];
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

- (BOOL) windowShouldClose:(NSWindow *)window
{

#pragma unused(window)
	
	if(self.compactDiscOperationQueue.operations.count)
		return NO;
	else	
		return YES;
}

- (void) setDisk:(DADiskRef)disk
{
	if(disk != _disk) {
		if(_disk)
			CFRelease(_disk), _disk = NULL;
		
		self.compactDisc = nil;
		self.driveInformation = nil;
		
		[self.networkOperationQueue cancelAllOperations];
		[self.compactDiscOperationQueue cancelAllOperations];
		
		if(disk) {
			_disk = DADiskCopyWholeDisk(disk);
			self.compactDisc = [CompactDisc compactDiscWithDADiskRef:self.disk inManagedObjectContext:self.managedObjectContext];
			self.driveInformation = [DriveInformation driveInformationWithDADiskRef:self.disk inManagedObjectContext:self.managedObjectContext];

			if(!self.driveInformation.readOffset)
				NSLog(@"Read offset is not configured for drive %@", self.driveInformation.deviceIdentifier);
			
			// FIXME: Replace with calculated offset
			self.driveInformation.readOffset = [NSNumber numberWithInt:102];
			
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

// ========================================
// Copy the selected tracks to intermediate WAV files, then send to the encoder
- (IBAction) copySelectedTracks:(id)sender
{
	
#pragma unused(sender)
	
	SessionDescriptor *firstSession = self.compactDisc.firstSession;
	NSSet *selectedTracks = firstSession.selectedTracks;
	
	// Only allow one operation on the compact disc at a time
	if(0 == selectedTracks.count || self.compactDiscOperationQueue.operations.count) {
		NSBeep();
		return;
	}
	
	// Store the tracks to be extracted
	self.tracksToBeExtracted = selectedTracks;

	// Ensure the disc's MCN has been read
	if(!self.compactDisc.metadata.MCN)
		[self readMCN:sender];
	
	// Ensure ISRCs and pre-gaps have been read for the selected tracks
	for(TrackDescriptor *track in selectedTracks) {

		// Don't waste time re-reading a pre-existing ISRC
		if(!track.metadata.ISRC) {
			ISRCDetectionOperation *isrcDetectionOperation = [[ISRCDetectionOperation alloc] init];
			
			isrcDetectionOperation.disk = self.disk;
			isrcDetectionOperation.trackID = track.objectID;
			
			[self.compactDiscOperationQueue addOperation:isrcDetectionOperation];
		}

		// Grab pre-gaps
		if(!track.preGap) {
			PreGapDetectionOperation *preGapDetectionOperation = [[PreGapDetectionOperation alloc] init];
			
			preGapDetectionOperation.disk = self.disk;
			preGapDetectionOperation.trackID = track.objectID;
			
			[self.compactDiscOperationQueue addOperation:preGapDetectionOperation];
		}
	}

	// Use the specified temporary directory if it exists, otherwise try the default and fall back to /tmp
	NSString *temporaryDirectory = [[NSUserDefaults standardUserDefaults] stringForKey:@"Temporary Directory"];
	if(!temporaryDirectory)
		temporaryDirectory = NSTemporaryDirectory();
	if(!temporaryDirectory)
		temporaryDirectory = @"/tmp";
	
	for(TrackDescriptor *track in selectedTracks) {
		ExtractionOperation *trackExtractionOperation = [[ExtractionOperation alloc] init];

		// Generate a random filename
		NSString *temporaryFilename = nil;
		do {
			NSString *randomFilename = [NSString stringWithFormat:@"Rip %x.wav", random()];
			temporaryFilename = [temporaryDirectory stringByAppendingPathComponent:randomFilename];
		} while([[NSFileManager defaultManager] fileExistsAtPath:temporaryFilename]);
		
		trackExtractionOperation.disk = self.disk;
		trackExtractionOperation.sectors = track.sectorRange;
		trackExtractionOperation.allowedSectors = self.compactDisc.firstSession.sectorRange;
		trackExtractionOperation.trackIDs = [NSArray arrayWithObject:track.objectID];
		trackExtractionOperation.readOffset = self.driveInformation.readOffset;
		trackExtractionOperation.URL = [NSURL fileURLWithPath:temporaryFilename];
		
		[self.compactDiscOperationQueue addOperation:trackExtractionOperation];
	}
}

- (IBAction) copyImage:(id)sender
{

#pragma unused(sender)

	// Only allow one operation on the compact disc at a time
	if(self.compactDiscOperationQueue.operations.count) {
		NSBeep();
		return;
	}
	
	// Store the tracks to be extracted
	self.tracksToBeExtracted = self.compactDisc.firstSession.tracks;

	// Use the specified temporary directory if it exists, otherwise try the default and fall back to /tmp
	NSString *temporaryDirectory = [[NSUserDefaults standardUserDefaults] stringForKey:@"Temporary Directory"];
	if(!temporaryDirectory)
		temporaryDirectory = NSTemporaryDirectory();
	if(!temporaryDirectory)
		temporaryDirectory = @"/tmp";

	ExtractionOperation *imageExtractionOperation = [[ExtractionOperation alloc] init];
	
	// Generate a random filename
	NSString *temporaryFilename = nil;
	do {
		NSString *randomFilename = [NSString stringWithFormat:@"Rip %x.wav", random()];
		temporaryFilename = [temporaryDirectory stringByAppendingPathComponent:randomFilename];
	} while([[NSFileManager defaultManager] fileExistsAtPath:temporaryFilename]);
	
	imageExtractionOperation.disk = self.disk;
	imageExtractionOperation.sectors = self.compactDisc.firstSession.sectorRange;
	imageExtractionOperation.allowedSectors = self.compactDisc.firstSession.sectorRange;
	imageExtractionOperation.trackIDs = [self.compactDisc.firstSession.tracks valueForKey:@"objectID"];
	imageExtractionOperation.readOffset = self.driveInformation.readOffset;
	imageExtractionOperation.URL = [NSURL fileURLWithPath:temporaryFilename];
	
	[self.compactDiscOperationQueue addOperation:imageExtractionOperation];
}

- (IBAction) detectPreGaps:(id)sender
{

#pragma unused(sender)
	
	NSSet *selectedTracks = self.compactDisc.firstSession.selectedTracks;
	
	// Only allow one operation on the compact disc at a time
	if(0 == selectedTracks.count || self.compactDiscOperationQueue.operations.count) {
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

- (IBAction) readMCN:(id)sender
{
	
#pragma unused(sender)

	// Only allow one operation on the compact disc at a time
	if(self.compactDiscOperationQueue.operations.count) {
		NSBeep();
		return;
	}

	MCNDetectionOperation *mcnDetectionOperation = [[MCNDetectionOperation alloc] init];
	
	mcnDetectionOperation.disk = self.disk;
	mcnDetectionOperation.compactDiscID = self.compactDisc.objectID;
	
	[self.compactDiscOperationQueue addOperation:mcnDetectionOperation];
}

- (IBAction) readISRCs:(id)sender
{

#pragma unused(sender)
	
	NSSet *selectedTracks = self.compactDisc.firstSession.selectedTracks;
	
	// Only allow one operation on the compact disc at a time
	if(0 == selectedTracks.count || self.compactDiscOperationQueue.operations.count) {
		NSBeep();
		return;
	}
	
	for(TrackDescriptor *track in selectedTracks) {
		ISRCDetectionOperation *isrcDetectionOperation = [[ISRCDetectionOperation alloc] init];
		
		isrcDetectionOperation.disk = self.disk;
		isrcDetectionOperation.trackID = track.objectID;
		
		[self.compactDiscOperationQueue addOperation:isrcDetectionOperation];
	}
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

- (IBAction) editTags:(id)sender
{
	
#pragma unused(sender)
	
	TagEditingSheetController *tagEditingSheetController = [[TagEditingSheetController alloc] init];		
	[tagEditingSheetController setTrackDescriptorObjectIDs:[self.compactDisc.firstSession.orderedTracks valueForKey:@"objectID"]];
	tagEditingSheetController.sortDescriptors = [_trackController sortDescriptors];
	tagEditingSheetController.selectionIndexes = [_trackController selectionIndexes];
	
	NSLog(@"%@", tagEditingSheetController.sortDescriptors);
	NSLog(@"%@", tagEditingSheetController.selectionIndexes);
	
	[[NSApplication sharedApplication] beginSheet:tagEditingSheetController.window 
								   modalForWindow:self.window
									modalDelegate:self 
								   didEndSelector:@selector(showTagEditingSheetDidEnd:returnCode:contextInfo:) 
									  contextInfo:tagEditingSheetController];	
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

#pragma unused(operation)

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
	
	// Create a dictionary to hold the actual checksums of the extracted audio
	NSMutableDictionary *actualAccurateRipChecksums = nil;
	
	// If trackIDs is set, the ExtractionOperation represents one or more whole tracks (and not an arbitrary range of sectors)
	// If this is the case, calculate the AccurateRip checksum(s) for the extracted tracks
	if(operation.trackIDs) {
		NSUInteger sectorOffset = 0;
		actualAccurateRipChecksums = [NSMutableDictionary dictionary];
		
		for(NSManagedObjectID *trackID in operation.trackIDs) {
			NSManagedObject *managedObject = [self.managedObjectContext objectWithID:trackID];
			if(![managedObject isKindOfClass:[TrackDescriptor class]])
				continue;
			
			TrackDescriptor *track = (TrackDescriptor *)managedObject;			
			SectorRange *trackSectorRange = track.sectorRange;
			
			// Since a file may contain multiple non-sequential tracks, there is not a 1:1 correspondence between
			// LBAs on the disc and sample frame offsets in the file.  Adjust for that here
			SectorRange *adjustedSectorRange = [SectorRange sectorRangeWithFirstSector:sectorOffset sectorCount:trackSectorRange.length];
			sectorOffset += trackSectorRange.length;
			
			NSUInteger accurateRipChecksum = calculateAccurateRipChecksumForFileRegion(operation.URL, 
																					   adjustedSectorRange.firstSector,
																					   adjustedSectorRange.lastSector,
																					   self.compactDisc.firstSession.firstTrack.number.unsignedIntegerValue == track.number.unsignedIntegerValue,
																					   self.compactDisc.firstSession.lastTrack.number.unsignedIntegerValue == track.number.unsignedIntegerValue);
			
			// Since Core Data only stores signed integers, cast the unsigned checksum to signed for storage
			[actualAccurateRipChecksums setObject:[NSNumber numberWithInt:(int32_t)accurateRipChecksum]
										   forKey:track.objectID];			
		}
	}
	
	// If this disc was found in Accurate Rip, verify the checksum(s) if whole tracks were extracted
	if(self.compactDisc.accurateRipDisc && operation.trackIDs) {
		BOOL allTracksWereAccuratelyExtracted = YES;

		for(NSManagedObjectID *trackID in operation.trackIDs) {
			NSManagedObject *managedObject = [self.managedObjectContext objectWithID:trackID];
			if(![managedObject isKindOfClass:[TrackDescriptor class]])
				continue;
			
			TrackDescriptor *track = (TrackDescriptor *)managedObject;			

			AccurateRipTrackRecord *accurateRipTrack = [self.compactDisc.accurateRipDisc trackNumber:track.number.unsignedIntegerValue];
			NSNumber *trackActualAccurateRipChecksum = [actualAccurateRipChecksums objectForKey:track.objectID];
			
			if(accurateRipTrack && accurateRipTrack.checksum.unsignedIntegerValue != trackActualAccurateRipChecksum.unsignedIntegerValue) {
				allTracksWereAccuratelyExtracted = NO;				
#if DEBUG
				NSLog(@"AccurateRip checksums don't match.  Expected %x, got %x", accurateRipTrack.checksum.unsignedIntegerValue, trackActualAccurateRipChecksum.unsignedIntegerValue);
#endif
			}
#if DEBUG
			else
				NSLog(@"Track %@ accurately ripped, confidence %@", track.number, accurateRipTrack.confidenceLevel);
#endif
		}

		// If all tracks were accurately ripped, ship the tracks/image off to the encoder
		if(allTracksWereAccuratelyExtracted) {
			ExtractionRecord *extractionRecord = [self createExtractionRecordForOperation:operation checksums:actualAccurateRipChecksums];
			[[EncoderManager sharedEncoderManager] encodeURL:operation.URL extractionRecord:extractionRecord error:NULL];
		}
	}
	// Re-rip the tracks if any C2 error flags were returned
	else if(operation.errorFlags.countOfOnes) {
		
	}
	// No C2 errors, pass the track to the encoder
	else {
		ExtractionRecord *extractionRecord = [self createExtractionRecordForOperation:operation checksums:actualAccurateRipChecksums];
		[[EncoderManager sharedEncoderManager] encodeURL:operation.URL extractionRecord:extractionRecord error:NULL];
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
	NSManagedObject *managedObject = [self.managedObjectContext objectWithID:operation.trackID];
	[self.managedObjectContext refreshObject:managedObject mergeChanges:YES];
}

- (void) MCNDetectionOperationStarted:(MCNDetectionOperation *)operation
{

#pragma unused(operation)

}

- (void) MCNDetectionOperationStopped:(MCNDetectionOperation *)operation
{
	NSParameterAssert(nil != operation);
	
	if(operation.error || operation.isCancelled) {
		if(operation.error)
			[self presentError:operation.error modalForWindow:self.window delegate:nil didPresentSelector:NULL contextInfo:NULL];
		return;
	}
	
	// Refresh the disc's metadata, to pull in the MCN set in the worker thread
	NSManagedObject *managedObject = [self.managedObjectContext objectWithID:operation.compactDiscID];
	if(![managedObject isKindOfClass:[CompactDisc class]])
		return;
	
	CompactDisc *disc = (CompactDisc *)managedObject;
	[self.managedObjectContext refreshObject:disc.metadata mergeChanges:YES];
}

- (void) ISRCDetectionOperationStarted:(ISRCDetectionOperation *)operation
{

#pragma unused(operation)

}

- (void) ISRCDetectionOperationStopped:(ISRCDetectionOperation *)operation
{
	NSParameterAssert(nil != operation);

	if(operation.error || operation.isCancelled) {
		if(operation.error)
			[self presentError:operation.error modalForWindow:self.window delegate:nil didPresentSelector:NULL contextInfo:NULL];
		return;
	}
	
	// Refresh the track's metadata, to pull in the ISRC set in the worker thread
	NSManagedObject *managedObject = [self.managedObjectContext objectWithID:operation.trackID];
	if(![managedObject isKindOfClass:[TrackDescriptor class]])
		return;

	TrackDescriptor *track = (TrackDescriptor *)managedObject;
	[self.managedObjectContext refreshObject:track.metadata mergeChanges:YES];
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
	NSManagedObject *managedObject = [self.managedObjectContext objectWithID:operation.compactDiscID];
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
}

- (void) showTagEditingSheetDidEnd:(NSWindow *)sheet returnCode:(int)returnCode contextInfo:(void *)contextInfo
{
	NSParameterAssert(nil != sheet);
	NSParameterAssert(NULL != contextInfo);
	
	[sheet orderOut:self];
	
	TagEditingSheetController *tagEditingSheetController = (TagEditingSheetController *)contextInfo;
	
	if(NSCancelButton == returnCode)
		return;
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

- (ExtractionRecord *) createExtractionRecordForOperation:(ExtractionOperation *)operation checksums:(NSDictionary *)checksums
{
	NSParameterAssert(nil != operation);
	
	ExtractionRecord *extractionRecord = [NSEntityDescription insertNewObjectForEntityForName:@"ExtractionRecord" 
																	   inManagedObjectContext:self.managedObjectContext];
	 
	extractionRecord.disc = self.compactDisc;
	extractionRecord.date = [NSDate date];
	extractionRecord.drive = self.driveInformation;
	extractionRecord.errorFlags = operation.errorFlags;
	extractionRecord.MD5 = operation.MD5;
	extractionRecord.SHA1 = operation.SHA1;

	if(operation.trackIDs) {		
		for(NSManagedObjectID *trackID in operation.trackIDs) {
			NSManagedObject *managedObject = [self.managedObjectContext objectWithID:trackID];
			if(![managedObject isKindOfClass:[TrackDescriptor class]])
				continue;
			
			TrackDescriptor *track = (TrackDescriptor *)managedObject;			

			ExtractedTrackRecord *extractedTrackRecord = [NSEntityDescription insertNewObjectForEntityForName:@"ExtractedTrackRecord" 
																					   inManagedObjectContext:self.managedObjectContext];
		
			extractedTrackRecord.track = track;		
			extractedTrackRecord.accurateRipChecksum = [checksums objectForKey:track.objectID];
		
			[extractionRecord addTracksObject:extractedTrackRecord];
		}
	}
	
	return extractionRecord;
}

- (void) createCueSheetSavePanelDidEnd:(NSSavePanel *)sheet returnCode:(int)returnCode  contextInfo:(void *)contextInfo
{
	if(NSCancelButton == returnCode)
		return;
	
	NSURL *cueSheetURL = [sheet URL];
	
	NSError *error = nil;
	if(![self writeCueSheetToURL:cueSheetURL error:&error])
		[self presentError:error modalForWindow:self.window delegate:nil didPresentSelector:NULL contextInfo:NULL];
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
		[cueSheetString appendFormat:@"TRACK %@ AUDIO\n", trackDescriptor.number];

		// Index
		CDMSF trackMSF = CDConvertLBAToMSF(trackDescriptor.firstSector.integerValue);
		[cueSheetString appendFormat:@"  INDEX %02i:%02i:%02i\n", trackMSF.minute, trackMSF.second, trackMSF.frame];
		
		// Pregap
		if(trackDescriptor.preGap) {
			CDMSF trackPreGapMSF = CDConvertLBAToMSF(trackDescriptor.preGap.integerValue - 150);
			[cueSheetString appendFormat:@"  PREGAP %02i:%02i:%02i\n", trackPreGapMSF.minute, trackPreGapMSF.second, trackPreGapMSF.frame];
		}

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

@end
