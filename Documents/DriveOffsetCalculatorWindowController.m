/*
 *  Copyright (C) 2008 Stephen F. Booth <me@sbooth.org>
 *  All Rights Reserved
 */

#import "DriveOffsetCalculatorWindowController.h"

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
NSString * const	kOperationQueueKVOContext				= @"org.sbooth.Rip.DriveOffsetCalculatorWindowController.OperationQueue.KVOContext";

@interface DriveOffsetCalculatorWindowController ()
@property (assign) CompactDisc * compactDisc;
@property (assign) DriveInformation * driveInformation;
@end

@implementation DriveOffsetCalculatorWindowController

@synthesize disk = _disk;
@synthesize compactDisc = _compactDisc;
@synthesize driveInformation = _driveInformation;

@synthesize operationQueue = _operationQueue;

- (id) init
{
	if((self = [super initWithWindowNibName:@"DriveOffsetCalculatorWindow"])) {
		_operationQueue = [[NSOperationQueue alloc] init];
		
		// Observe changes in the compact disc operations array, to be notified when each operation starts and stops
		[self.operationQueue addObserver:self forKeyPath:@"operations" options:(NSKeyValueObservingOptionOld |  NSKeyValueObservingOptionNew) context:kOperationQueueKVOContext];
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
	[_accurateRipQueryTextField setTextColor:[NSColor disabledControlTextColor]];
	[_extractionTextField setTextColor:[NSColor disabledControlTextColor]];
	[_offsetCalculationTextField setTextColor:[NSColor disabledControlTextColor]];

	
	// Automatically sort the possible offsets based on confidence level
	NSSortDescriptor *confidenceLevelSortDescriptor = [[NSSortDescriptor alloc] initWithKey:@"confidenceLevel" ascending:NO];
	[_possibleOffsetsArrayController setSortDescriptors:[NSArray arrayWithObject:confidenceLevelSortDescriptor]];
	
	[self.window center];
}

- (void) observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context
{
	if(kOperationQueueKVOContext == context) {
		NSInteger changeKind = [[change objectForKey:NSKeyValueChangeKindKey] integerValue];
		
		if(NSKeyValueChangeInsertion == changeKind) {
			for(NSOperation *operation in [change objectForKey:NSKeyValueChangeNewKey]) {
			}
		}
		else if(NSKeyValueChangeRemoval == changeKind) {
			for(NSOperation *operation in [change objectForKey:NSKeyValueChangeOldKey]) {
				if([operation isKindOfClass:[AccurateRipQueryOperation class]]) {
					[_accurateRipQueryProgressIndicator unbind:@"animate"];
					
					AccurateRipQueryOperation *accurateRipQueryOperation = (AccurateRipQueryOperation *)operation;
					
					if(accurateRipQueryOperation.error || accurateRipQueryOperation.isCancelled) {
						if(accurateRipQueryOperation.error)
							[self presentError:accurateRipQueryOperation.error modalForWindow:self.window delegate:nil didPresentSelector:NULL contextInfo:NULL];
						
						continue;
					}
					
					// Refresh ourselves, to pull in the AccurateRip data created by the worker thread
					NSManagedObject *managedObject = [self.managedObjectContext objectWithID:accurateRipQueryOperation.compactDiscID];
					[self.managedObjectContext refreshObject:managedObject mergeChanges:YES];
				}
				else if([operation isKindOfClass:[ExtractionOperation class]]) {
					[_extractionProgressIndicator unbind:@"animate"];
					
					ExtractionOperation *extractionOperation = (ExtractionOperation *)operation;
					
					if(extractionOperation.error || extractionOperation.isCancelled) {
						if(extractionOperation.error)
							[self presentError:extractionOperation.error modalForWindow:self.window delegate:nil didPresentSelector:NULL contextInfo:NULL];
						
						continue;
					}
					
				}
				else if([operation isKindOfClass:[ReadOffsetCalculationOperation class]]) {
					[_offsetCalculationProgressIndicator unbind:@"animate"];
					
					ReadOffsetCalculationOperation *readOffsetCalculationOperation = (ReadOffsetCalculationOperation *)operation;
					
					if(readOffsetCalculationOperation.error || readOffsetCalculationOperation.isCancelled) {
						if(readOffsetCalculationOperation.error)
							[self presentError:readOffsetCalculationOperation.error modalForWindow:self.window delegate:nil didPresentSelector:NULL contextInfo:NULL];
						
						continue;
					}
					
//					NSLog(@"Offset calculated: %@", readOffsetCalculationOperation.readOffset);
					
				}
			}
		}
	}
	else if([object isKindOfClass:[NSOperation class]]) {
		NSOperation *operation = object;
		
		if([keyPath isEqualToString:@"isExecuting"]) {
			if([operation isKindOfClass:[AccurateRipQueryOperation class]])
				[_accurateRipQueryTextField setTextColor:(operation.isExecuting ? [NSColor controlTextColor] : [NSColor disabledControlTextColor])];
			else if([operation isKindOfClass:[ExtractionOperation class]])
				[_extractionTextField setTextColor:(operation.isExecuting ? [NSColor controlTextColor] : [NSColor disabledControlTextColor])];
			else if([operation isKindOfClass:[ReadOffsetCalculationOperation class]])
				[_offsetCalculationTextField setTextColor:(operation.isExecuting ? [NSColor controlTextColor] : [NSColor disabledControlTextColor])];
		}
		else if([keyPath isEqualToString:@"isFinished"]) {
			if([operation isKindOfClass:[AccurateRipQueryOperation class]])
				[_accurateRipQueryTextField setTextColor:(operation.isFinished ? [NSColor disabledControlTextColor] : [NSColor controlTextColor])];
			else if([operation isKindOfClass:[ExtractionOperation class]])
				[_extractionTextField setTextColor:(operation.isFinished ? [NSColor disabledControlTextColor] : [NSColor controlTextColor])];
			else if([operation isKindOfClass:[ReadOffsetCalculationOperation class]]) {
				[_offsetCalculationTextField setTextColor:(operation.isFinished ? [NSColor disabledControlTextColor] : [NSColor controlTextColor])];
				if(operation.isFinished)
					[_possibleOffsetsArrayController addObjects:[operation valueForKey:@"possibleReadOffsets"]];
			}
		}
	}
	else
		[super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
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
		self.driveInformation = nil;
		
		if(disk) {
			_disk = DADiskCopyWholeDisk(disk);
			self.compactDisc = [CompactDisc compactDiscWithDADiskRef:self.disk inManagedObjectContext:self.managedObjectContext];
			self.driveInformation = [DriveInformation driveInformationWithDADiskRef:self.disk inManagedObjectContext:self.managedObjectContext];
		}
	}
}

- (IBAction) determineDriveOffset:(id)sender
{
	
#pragma unused(sender)
	
	// Set up  operations for querying AccurateRip and extracting the audio
	AccurateRipQueryOperation *accurateRipQueryOperation = [[AccurateRipQueryOperation alloc] init];
	accurateRipQueryOperation.compactDiscID = self.compactDisc.objectID;
	
	[_accurateRipQueryProgressIndicator bind:@"animate" toObject:accurateRipQueryOperation withKeyPath:@"isExecuting" options:nil];	

	[accurateRipQueryOperation addObserver:self forKeyPath:@"isExecuting" options:0 context:NULL];
	[accurateRipQueryOperation addObserver:self forKeyPath:@"isFinished" options:0 context:NULL];
	
	[self.operationQueue addOperation:accurateRipQueryOperation];

	// Extraction
	NSSet *tracksToScan = [self.compactDisc.firstSession.tracks filteredSetUsingPredicate:[NSPredicate predicateWithFormat:@"number == 2"]];
//	NSSet *tracksToScan = self.compactDisc.firstSession.orderedTracks;
	for(TrackDescriptor *track in tracksToScan) {
		SectorRange *trackSectorRange = [track sectorRange];
		
		// AccurateRip offset checksums start at six seconds into the file
		NSUInteger sixSecondPointSector = trackSectorRange.firstSector + (6 * CDDA_SECTORS_PER_SECOND);
		
		SectorRange *sectorsToExtract = [SectorRange sectorRangeWithFirstSector:(sixSecondPointSector - MAXIMUM_OFFSET_TO_CHECK_IN_SECTORS)
																	sectorCount:(2 * MAXIMUM_OFFSET_TO_CHECK_IN_SECTORS)];
		
		// Create a temporary URL for the extracted audio
		NSURL *temporaryURL = temporaryURLWithExtension(@"wav");
		
		ExtractionOperation *extractionOperation = [[ExtractionOperation alloc] init];
		
		extractionOperation.disk = self.disk;
		extractionOperation.sectors = sectorsToExtract;
		extractionOperation.allowedSectors = self.compactDisc.firstSession.sectorRange;
		extractionOperation.URL = temporaryURL;
		
		// Offset calculation
		ReadOffsetCalculationOperation *offsetCalculationOperation = [[ReadOffsetCalculationOperation alloc] init];
		
		offsetCalculationOperation.URL = extractionOperation.URL;
		offsetCalculationOperation.trackDescriptorID = track.objectID;
		offsetCalculationOperation.maximumOffsetToCheck = [NSNumber numberWithUnsignedInteger:(MAXIMUM_OFFSET_TO_CHECK_IN_SECTORS * AUDIO_FRAMES_PER_CDDA_SECTOR)];
		
		// UI bindings
		[_extractionProgressIndicator bind:@"animate" toObject:extractionOperation withKeyPath:@"isExecuting" options:nil];
		[_offsetCalculationProgressIndicator bind:@"animate" toObject:offsetCalculationOperation withKeyPath:@"isExecuting" options:nil];
				
		[extractionOperation addObserver:self forKeyPath:@"isExecuting" options:0 context:NULL];
		[extractionOperation addObserver:self forKeyPath:@"isFinished" options:0 context:NULL];
		
		[offsetCalculationOperation addObserver:self forKeyPath:@"isExecuting" options:0 context:NULL];
		[offsetCalculationOperation addObserver:self forKeyPath:@"isFinished" options:0 context:NULL];
		
		
		// Set up operation dependencies
		[extractionOperation addDependency:accurateRipQueryOperation];
		[offsetCalculationOperation addDependency:extractionOperation];
		
		// Go!
		[self.operationQueue addOperation:extractionOperation];
		[self.operationQueue addOperation:offsetCalculationOperation];
	}
}

- (IBAction) acceptOffset:(id)sender
{
	
#pragma unused(sender)

	if(self.operationQueue.operations.count) {
		NSBeep();
		return;
	}

	self.driveInformation.readOffset = [[_possibleOffsetsArrayController selection] valueForKey:kReadOffsetKey];
	
//	[self.window orderOut:sender];
	[[NSApplication sharedApplication] endSheet:self.window returnCode:NSOKButton];
}

- (IBAction) cancel:(id)sender
{
	
#pragma unused(sender)

	[self.operationQueue cancelAllOperations];
//	[self.window orderOut:sender];
	[[NSApplication sharedApplication] endSheet:self.window returnCode:NSCancelButton];
}

@end
