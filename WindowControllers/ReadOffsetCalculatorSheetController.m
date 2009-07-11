/*
 *  Copyright (C) 2008 - 2009 Stephen F. Booth <me@sbooth.org>
 *  All Rights Reserved
 */

#import "ReadOffsetCalculatorSheetController.h"

#import "CompactDisc.h"
#import "SessionDescriptor.h"
#import "TrackDescriptor.h"

#import "AccurateRipDiscRecord.h"
#import "AccurateRipTrackRecord.h"
#import "AccurateRipUtilities.h"

#import "DriveInformation.h"

#import "SectorRange.h"

#import "AccurateRipQueryOperation.h"
#import "ExtractionOperation.h"
#import "ReadOffsetCalculationOperation.h"

#import "CDDAUtilities.h"
#import "FileUtilities.h"

// ========================================
// The number of sectors which will be scanned during offset detection
// ========================================
#define MAXIMUM_OFFSET_TO_CHECK_IN_SECTORS 8

// ========================================
// Context objects for observeValueForKeyPath:ofObject:change:context:
// ========================================
static NSString * const kQueryAccurateRipKVOContext		= @"org.sbooth.Rip.ReadOffsetCalculatorSheetController.AccurateRipQueryKVOContext";
static NSString * const kExtractAudioKVOContext			= @"org.sbooth.Rip.ReadOffsetCalculatorSheetController.ExtractAudioKVOContext";
static NSString * const kCalculateOffsetsKVOContext		= @"org.sbooth.Rip.ReadOffsetCalculatorSheetController.CalculateOffsetsKVOContext";

@interface ReadOffsetCalculatorSheetController ()
@property (assign) CompactDisc * compactDisc;
@property (assign) DriveInformation * driveInformation;
@property (assign) NSManagedObjectContext * managedObjectContext;
@property (assign) NSOperationQueue * operationQueue;
@property (assign) BOOL possibleOffsetsShown;
@end

@interface ReadOffsetCalculatorSheetController (Callbacks)
- (void) didPresentErrorWithRecovery:(BOOL)didRecover contextInfo:(void *)contextInfo;
@end

@interface ReadOffsetCalculatorSheetController (Private)
- (void) accurateRipQueryOperationDidFinish:(AccurateRipQueryOperation *)operation;
- (void) readOffsetCalculationOperationDidFinish:(ReadOffsetCalculationOperation *)operation;
@end

@implementation ReadOffsetCalculatorSheetController

@synthesize disk = _disk;
@synthesize compactDisc = _compactDisc;
@synthesize driveInformation = _driveInformation;

@synthesize managedObjectContext = _managedObjectContext;
@synthesize operationQueue = _operationQueue;

@synthesize possibleOffsetsShown = _possibleOffsetsShown;

- (id) init
{
	if((self = [super initWithWindowNibName:@"ReadOffsetCalculatorSheet"])) {
		// Create our own context for accessing the store
		self.managedObjectContext = [[NSManagedObjectContext alloc] init];
		[self.managedObjectContext setPersistentStoreCoordinator:[[[NSApplication sharedApplication] delegate] persistentStoreCoordinator]];

		// Register to receive NSManagedObjectContextDidSaveNotification to keep our MOC in sync
		[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(managedObjectContextDidSave:) name:NSManagedObjectContextDidSaveNotification object:nil];

		self.operationQueue = [[NSOperationQueue alloc] init];

		_possibleOffsetsShown = YES;
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
	[self togglePossibleOffsetsShown:self];
	
	// Automatically sort the possible offsets based on confidence level
	NSSortDescriptor *confidenceLevelSortDescriptor = [[NSSortDescriptor alloc] initWithKey:@"confidenceLevel" ascending:NO];
	[_possibleOffsetsArrayController setSortDescriptors:[NSArray arrayWithObject:confidenceLevelSortDescriptor]];
}

- (void) observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context
{
	if(kQueryAccurateRipKVOContext == context) {
		AccurateRipQueryOperation *operation = (AccurateRipQueryOperation *)object;
		
		if([keyPath isEqualToString:@"isExecuting"]) {
			if([operation isExecuting]) {
				if([NSThread isMainThread])
					[_statusTextField setStringValue:NSLocalizedString(@"Checking for disc in AccurateRip", @"")];
				else
					[_statusTextField performSelectorOnMainThread:@selector(setStringValue:) withObject:NSLocalizedString(@"Checking for disc in AccurateRip", @"") waitUntilDone:NO];
			}
		}
		else if([keyPath isEqualToString:@"isCancelled"] || [keyPath isEqualToString:@"isFinished"]) {
			[operation removeObserver:self forKeyPath:@"isExecuting"];
			[operation removeObserver:self forKeyPath:@"isCancelled"];
			[operation removeObserver:self forKeyPath:@"isFinished"];
			
			if(operation.error) {
				[self.operationQueue cancelAllOperations];
				
				[self presentError:operation.error 
					modalForWindow:self.window 
						  delegate:self 
				didPresentSelector:@selector(didPresentErrorWithRecovery:contextInfo:) 
					   contextInfo:NULL];
			}
			
			if([operation isFinished]) {
				if([NSThread isMainThread])
					[self accurateRipQueryOperationDidFinish:operation];
				else
					[self performSelectorOnMainThread:@selector(accurateRipQueryOperationDidFinish:) withObject:operation waitUntilDone:NO];
			}
			
		}
	}
	else if(kExtractAudioKVOContext == context) {
		ExtractionOperation *operation = (ExtractionOperation *)object;
		
		if([keyPath isEqualToString:@"isExecuting"]) {
			if([operation isExecuting]) {
				if([NSThread isMainThread])
					[_statusTextField setStringValue:NSLocalizedString(@"Extracting audio", @"")];
				else
					[_statusTextField performSelectorOnMainThread:@selector(setStringValue:) withObject:NSLocalizedString(@"Extracting audio", @"") waitUntilDone:NO];
			}
		}
		else if([keyPath isEqualToString:@"isCancelled"] || [keyPath isEqualToString:@"isFinished"]) {
			[operation removeObserver:self forKeyPath:@"isExecuting"];
			[operation removeObserver:self forKeyPath:@"isCancelled"];
			[operation removeObserver:self forKeyPath:@"isFinished"];
		}
	}
	else if(kCalculateOffsetsKVOContext == context) {
		ReadOffsetCalculationOperation *operation = (ReadOffsetCalculationOperation *)object;
		
		if([keyPath isEqualToString:@"isExecuting"]) {
			if([operation isExecuting]) {
				if([NSThread isMainThread])
					[_statusTextField setStringValue:NSLocalizedString(@"Calculating possible read offsets", @"")];
				else
					[_statusTextField performSelectorOnMainThread:@selector(setStringValue:) withObject:NSLocalizedString(@"Calculating possible read offsets", @"") waitUntilDone:NO];
			}
		}
		else if([keyPath isEqualToString:@"isCancelled"] || [keyPath isEqualToString:@"isFinished"]) {
			[operation removeObserver:self forKeyPath:@"isExecuting"];
			[operation removeObserver:self forKeyPath:@"isCancelled"];
			[operation removeObserver:self forKeyPath:@"isFinished"];

			if([operation isFinished]) {
				if([NSThread isMainThread])
					[self readOffsetCalculationOperationDidFinish:operation];
				else
					[self performSelectorOnMainThread:@selector(readOffsetCalculationOperationDidFinish:) withObject:operation waitUntilDone:NO];
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
		}
	}
}

- (void) beginReadOffsetCalculatorSheetForWindow:(NSWindow *)window modalDelegate:(id)modalDelegate didEndSelector:(SEL)didEndSelector contextInfo:(void *)contextInfo
{
	NSParameterAssert(nil != window);

	[[NSApplication sharedApplication] beginSheet:self.window
								   modalForWindow:window
									modalDelegate:modalDelegate
								   didEndSelector:didEndSelector
									  contextInfo:contextInfo];
	
	[_progressIndicator startAnimation:self];

	// Set up  operations for querying AccurateRip and extracting the audio
	AccurateRipQueryOperation *accurateRipQueryOperation = [[AccurateRipQueryOperation alloc] init];

	accurateRipQueryOperation.compactDiscID = self.compactDisc.objectID;
	
	// Observe the operations' state
	[accurateRipQueryOperation addObserver:self forKeyPath:@"isExecuting" options:NSKeyValueObservingOptionNew context:kQueryAccurateRipKVOContext];
	[accurateRipQueryOperation addObserver:self forKeyPath:@"isCancelled" options:NSKeyValueObservingOptionNew context:kQueryAccurateRipKVOContext];
	[accurateRipQueryOperation addObserver:self forKeyPath:@"isFinished" options:NSKeyValueObservingOptionNew context:kQueryAccurateRipKVOContext];
		
	[self.operationQueue addOperation:accurateRipQueryOperation];
}

- (IBAction) acceptSuggestedOffset:(id)sender
{
	if(self.operationQueue.operations.count) {
		NSBeep();
		return;
	}

	// Use the offset with the highest confidence level
	// The user may have reordered the table, so we can't rely on the first object in arrangedObjects
	// being the offset with the highest confidence level
	NSSortDescriptor *confidenceLevelSortDescriptor = [[NSSortDescriptor alloc] initWithKey:@"confidenceLevel" ascending:NO];
	NSArray *sortedPossibleOffsets = [[_possibleOffsetsArrayController arrangedObjects] sortedArrayUsingDescriptors:[NSArray arrayWithObject:confidenceLevelSortDescriptor]];
	NSDictionary *highestConfidenceLevel = [sortedPossibleOffsets objectAtIndex:0];
	
	if(highestConfidenceLevel)
		self.driveInformation.readOffset = [highestConfidenceLevel valueForKey:kReadOffsetKey];
	
	// Save the changes
	if(self.managedObjectContext.hasChanges) {
		NSError *error = nil;
		if(![self.managedObjectContext save:&error])
			[self presentError:error modalForWindow:self.window delegate:self didPresentSelector:@selector(didPresentErrorWithRecovery:contextInfo:) contextInfo:NULL];
	}

	self.disk = NULL;
	
	[[NSApplication sharedApplication] endSheet:self.window returnCode:NSOKButton];
	[self.window orderOut:sender];
}

- (IBAction) cancel:(id)sender
{
	[self.operationQueue cancelAllOperations];
	self.disk = NULL;

	[[NSApplication sharedApplication] endSheet:self.window returnCode:NSCancelButton];
	[self.window orderOut:sender];
}

- (IBAction) togglePossibleOffsetsShown:(id)sender
{
	
#pragma unused(sender)
	
	// Adjust the window's frame to show or hide the possible offsets view
	NSRect currentWindowFrame = [self.window frame];
	NSRect newWindowFrame = currentWindowFrame;

	NSRect possibleOffsetsContainerFrame = [_possibleOffsetsView frame];

	// Shrink the window by the height of the possible offsets view, keeping the origin constant
	if(self.possibleOffsetsShown) {
		newWindowFrame.size.height -= possibleOffsetsContainerFrame.size.height;		
		newWindowFrame.origin.y	+= possibleOffsetsContainerFrame.size.height;
		self.possibleOffsetsShown = NO;
	}
	// Expand the window by the height of the possible offsets view
 	else {
		newWindowFrame.size.height += possibleOffsetsContainerFrame.size.height;
		newWindowFrame.origin.y	-= possibleOffsetsContainerFrame.size.height;
		self.possibleOffsetsShown = YES;
	}

	[_possibleOffsetsViewDisclosureButton setState:self.possibleOffsetsShown];
	[self.window setFrame:newWindowFrame display:YES animate:YES];	
}

- (IBAction) useSelectedOffset:(id)sender
{
	
#pragma unused(sender)
	
	if(self.operationQueue.operations.count) {
		NSBeep();
		return;
	}
	
	self.driveInformation.readOffset = [[_possibleOffsetsArrayController selection] valueForKey:kReadOffsetKey];
	
	// Save the changes
	if(self.managedObjectContext.hasChanges) {
		NSError *error = nil;
		if(![self.managedObjectContext save:&error])
			[self presentError:error modalForWindow:self.window delegate:self didPresentSelector:@selector(didPresentErrorWithRecovery:contextInfo:) contextInfo:NULL];
	}
	
	self.disk = NULL;

	[[NSApplication sharedApplication] endSheet:self.window returnCode:NSOKButton];
	[self.window orderOut:sender];
}

@end

@implementation ReadOffsetCalculatorSheetController (Callbacks)

- (void) didPresentErrorWithRecovery:(BOOL)didRecover contextInfo:(void *)contextInfo
{
	
#pragma unused(contextInfo)
	
	[[NSApplication sharedApplication] endSheet:self.window returnCode:(didRecover ? NSOKButton : NSCancelButton)];	
	[self.window orderOut:self];
}

@end

@implementation ReadOffsetCalculatorSheetController (Private)

- (void) accurateRipQueryOperationDidFinish:(AccurateRipQueryOperation *)operation
{
	NSParameterAssert(nil != operation);
	
	// If the operation didn't succeed, it isn't worthwhile to continue
	if(!self.compactDisc.accurateRipDiscs) {
		NSMutableDictionary *errorDictionary = [NSMutableDictionary dictionary];
		
		[errorDictionary setObject:NSLocalizedString(@"This disc cannot be used to calculate the read offset.", @"") forKey:NSLocalizedDescriptionKey];
		[errorDictionary setObject:NSLocalizedString(@"Drive offsets can only be determined using discs present in the AccurateRip database.", @"") forKey:NSLocalizedRecoverySuggestionErrorKey];
		
		NSError *error = [NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorNotConnectedToInternet userInfo:errorDictionary];
		
		[self presentError:error modalForWindow:self.window delegate:self didPresentSelector:@selector(didPresentErrorWithRecovery:contextInfo:) contextInfo:NULL];

		return;
	}
	
	// Form a union of the tracks that can be checked. A track can be checked if:
	// - It has an offset checksum from AccurateRip
	// - It is at least six seconds long (if it isn't it shouldn't have an offset checksum, but who knows)

	// First grab the tracks that contain offset checksums
	NSSet *allAccurateRipTracks = [self.compactDisc.accurateRipDiscs valueForKeyPath:@"@distinctUnionOfSets.tracks"];
	NSPredicate *accurateRipTracksPredicate = [NSPredicate predicateWithFormat:@"offsetChecksum != NULL"];
	NSSet *accurateRipTracksWithOffsetChecksums = [allAccurateRipTracks filteredSetUsingPredicate:accurateRipTracksPredicate];

	// If none were found, nothing can be done
	if(![accurateRipTracksWithOffsetChecksums count]) {
		NSMutableDictionary *errorDictionary = [NSMutableDictionary dictionary];
		
		[errorDictionary setObject:NSLocalizedString(@"This disc cannot be used to calculate the read offset.", @"") forKey:NSLocalizedDescriptionKey];
		[errorDictionary setObject:NSLocalizedString(@"Drive offsets can only be determined with AccurateRip key discs. This disc is not a key disc.", @"") forKey:NSLocalizedRecoverySuggestionErrorKey];
		
		NSError *error = [NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorNotConnectedToInternet userInfo:errorDictionary];
		
		[self presentError:error modalForWindow:self.window delegate:self didPresentSelector:@selector(didPresentErrorWithRecovery:contextInfo:) contextInfo:NULL];
		
		return;
	}

	// And grab the track objects that correspond to them
	NSArray *trackNumbers = [accurateRipTracksWithOffsetChecksums valueForKey:@"number"];
	NSPredicate *potentialTracksPredicate = [NSPredicate predicateWithFormat:@"number IN %@", trackNumbers];
	NSSet *potentialTracks = [self.compactDisc.firstSession.tracks filteredSetUsingPredicate:potentialTracksPredicate];

	// Extract a portion of the first track meeting our criteria that is at least six seconds long
	TrackDescriptor *trackToExtract = nil;
	for(TrackDescriptor *potentialTrack in potentialTracks) {
		// The track must be at least six seconds long (plus the buffer); if it isn't, skip it
		if(((6 * CDDA_SECTORS_PER_SECOND) + MAXIMUM_OFFSET_TO_CHECK_IN_SECTORS) > potentialTrack.sectorCount)
			continue;
		
		trackToExtract = potentialTrack;
		break;
	}
	
	if(!trackToExtract) {
		NSMutableDictionary *errorDictionary = [NSMutableDictionary dictionary];
		
		[errorDictionary setObject:NSLocalizedString(@"This disc cannot be used to calculate the read offset.", @"") forKey:NSLocalizedDescriptionKey];
		[errorDictionary setObject:NSLocalizedString(@"This disc does not contain any tracks that can be used for offset determination.", @"") forKey:NSLocalizedRecoverySuggestionErrorKey];
		
		NSError *error = [NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorNotConnectedToInternet userInfo:errorDictionary];
		
		[self presentError:error modalForWindow:self.window delegate:self didPresentSelector:@selector(didPresentErrorWithRecovery:contextInfo:) contextInfo:NULL];

		return;
	}
	
	SectorRange *trackSectorRange = [trackToExtract sectorRange];
	
	// AccurateRip offset checksums start at six seconds into the file
	NSUInteger sixSecondPointSector = trackSectorRange.firstSector + (6 * CDDA_SECTORS_PER_SECOND);
	
	SectorRange *sectorsToExtract = [SectorRange sectorRangeWithFirstSector:(sixSecondPointSector - MAXIMUM_OFFSET_TO_CHECK_IN_SECTORS)
																sectorCount:((2 * MAXIMUM_OFFSET_TO_CHECK_IN_SECTORS) + 1)];
	
	ExtractionOperation *extractionOperation = [[ExtractionOperation alloc] init];
	
	extractionOperation.disk = self.disk;
	extractionOperation.sectors = sectorsToExtract;
	extractionOperation.allowedSectors = self.compactDisc.firstSession.sectorRange;
	extractionOperation.URL = temporaryURLWithExtension(@"wav");
	extractionOperation.useC2 = NO;
	
	// Offset calculation
	ReadOffsetCalculationOperation *offsetCalculationOperation = [[ReadOffsetCalculationOperation alloc] init];
	
	offsetCalculationOperation.URL = extractionOperation.URL;
	offsetCalculationOperation.trackID = trackToExtract.objectID;
	offsetCalculationOperation.sixSecondPointSector = MAXIMUM_OFFSET_TO_CHECK_IN_SECTORS;
	offsetCalculationOperation.maximumOffsetToCheck = (MAXIMUM_OFFSET_TO_CHECK_IN_SECTORS * AUDIO_FRAMES_PER_CDDA_SECTOR);
	
	// Set up operation dependencies
	[offsetCalculationOperation addDependency:extractionOperation];
	
	[extractionOperation addObserver:self forKeyPath:@"isExecuting" options:NSKeyValueObservingOptionNew context:kExtractAudioKVOContext];
	[extractionOperation addObserver:self forKeyPath:@"isCancelled" options:NSKeyValueObservingOptionNew context:kExtractAudioKVOContext];
	[extractionOperation addObserver:self forKeyPath:@"isFinished" options:NSKeyValueObservingOptionNew context:kExtractAudioKVOContext];
	
	[offsetCalculationOperation addObserver:self forKeyPath:@"isExecuting" options:NSKeyValueObservingOptionNew context:kCalculateOffsetsKVOContext];
	[offsetCalculationOperation addObserver:self forKeyPath:@"isCancelled" options:NSKeyValueObservingOptionNew context:kCalculateOffsetsKVOContext];
	[offsetCalculationOperation addObserver:self forKeyPath:@"isFinished" options:NSKeyValueObservingOptionNew context:kCalculateOffsetsKVOContext];
	
	// Go!
	[self.operationQueue addOperation:extractionOperation];
	[self.operationQueue addOperation:offsetCalculationOperation];	
}

- (void) readOffsetCalculationOperationDidFinish:(ReadOffsetCalculationOperation *)operation
{
	NSParameterAssert(nil != operation);
	
	// If the operation didn't succeed, it isn't worthwhile to continue
	if(![operation.possibleReadOffsets count]) {
		NSMutableDictionary *errorDictionary = [NSMutableDictionary dictionary];
		
		[errorDictionary setObject:NSLocalizedString(@"Unable to determine any potential read offsets.", @"") forKey:NSLocalizedDescriptionKey];
		[errorDictionary setObject:NSLocalizedString(@"Please try again using a different compact disc or set the drive's read offset manually.", @"") forKey:NSLocalizedRecoverySuggestionErrorKey];
		
		NSError *error = [NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorNotConnectedToInternet userInfo:errorDictionary];
		
		[self presentError:error modalForWindow:self.window delegate:self didPresentSelector:@selector(didPresentErrorWithRecovery:contextInfo:) contextInfo:NULL];
		
		return;
	}
	
	[_possibleOffsetsArrayController addObjects:operation.possibleReadOffsets];
	
	[_statusTextField setStringValue:[NSString stringWithFormat:NSLocalizedString(@"Detected %i possible read offsets", @""), [[_possibleOffsetsArrayController arrangedObjects] count]]];
	[_progressIndicator stopAnimation:self];
	
	// The user may have reordered the table, so we can't rely on the first object in arrangedObjects
	// being the offset with the highest confidence level
	NSSortDescriptor *confidenceLevelSortDescriptor = [[NSSortDescriptor alloc] initWithKey:@"confidenceLevel" ascending:NO];
	NSArray *sortedPossibleOffsets = [[_possibleOffsetsArrayController arrangedObjects] sortedArrayUsingDescriptors:[NSArray arrayWithObject:confidenceLevelSortDescriptor]];
	
	NSDictionary *highestConfidenceLevel = nil;
	if([sortedPossibleOffsets count])
		highestConfidenceLevel = [sortedPossibleOffsets objectAtIndex:0];
	
	if(highestConfidenceLevel)
		[_suggestedOffsetTextField setIntegerValue:[[highestConfidenceLevel valueForKey:kReadOffsetKey] integerValue]];
}

@end
