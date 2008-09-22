/*
 *  Copyright (C) 2008 Stephen F. Booth <me@sbooth.org>
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
static NSString * const kOperationQueueKVOContext			= @"org.sbooth.Rip.ReadOffsetCalculatorSheetController.OperationQueue.KVOContext";

@interface ReadOffsetCalculatorSheetController ()
@property (assign) CompactDisc * compactDisc;
@property (assign) DriveInformation * driveInformation;
@property (assign) AccurateRipQueryOperation * accurateRipQueryOperation;
@property (assign) ExtractionOperation * extractionOperation;
@property (assign) ReadOffsetCalculationOperation * offsetCalculationOperation;
@property (assign) BOOL possibleOffsetsShown;
@end

@implementation ReadOffsetCalculatorSheetController

@synthesize disk = _disk;
@synthesize compactDisc = _compactDisc;
@synthesize driveInformation = _driveInformation;

@synthesize operationQueue = _operationQueue;

@synthesize accurateRipQueryOperation = _accurateRipQueryOperation;
@synthesize extractionOperation = _extractionOperation;
@synthesize offsetCalculationOperation = _offsetCalculationOperation;

@synthesize possibleOffsetsShown = _possibleOffsetsShown;

- (id) init
{
	if((self = [super initWithWindowNibName:@"ReadOffsetCalculatorSheet"])) {
		_operationQueue = [[NSOperationQueue alloc] init];
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

- (void) awakeFromNib
{
	[_accurateRipQueryTextField setTextColor:[NSColor disabledControlTextColor]];
	[_extractionTextField setTextColor:[NSColor disabledControlTextColor]];
	[_offsetCalculationTextField setTextColor:[NSColor disabledControlTextColor]];

	[self togglePossibleOffsetsShown:self];
	
	// Automatically sort the possible offsets based on confidence level
	NSSortDescriptor *confidenceLevelSortDescriptor = [[NSSortDescriptor alloc] initWithKey:@"confidenceLevel" ascending:NO];
	[_possibleOffsetsArrayController setSortDescriptors:[NSArray arrayWithObject:confidenceLevelSortDescriptor]];
}

- (void) observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context
{
	if(kOperationQueueKVOContext == context) {
		if(object == self.accurateRipQueryOperation) {
			if([keyPath isEqualToString:@"isExecuting"])
				[_accurateRipQueryTextField setTextColor:(self.accurateRipQueryOperation.isExecuting ? [NSColor controlTextColor] : [NSColor disabledControlTextColor])];
			else if([keyPath isEqualToString:@"isFinished"])
				[_accurateRipQueryTextField setTextColor:(self.accurateRipQueryOperation.isFinished ? [NSColor disabledControlTextColor] : [NSColor controlTextColor])];
		}
		else if(object == self.extractionOperation) {
			if([keyPath isEqualToString:@"isExecuting"])
				[_extractionTextField setTextColor:(self.extractionOperation.isExecuting ? [NSColor controlTextColor] : [NSColor disabledControlTextColor])];
			else if([keyPath isEqualToString:@"isFinished"])
				[_extractionTextField setTextColor:(self.extractionOperation.isFinished ? [NSColor disabledControlTextColor] : [NSColor controlTextColor])];
		}
		else if(object == self.offsetCalculationOperation) {
			if([keyPath isEqualToString:@"isExecuting"])
				[_offsetCalculationTextField setTextColor:(self.offsetCalculationOperation.isExecuting ? [NSColor controlTextColor] : [NSColor disabledControlTextColor])];
			else if([keyPath isEqualToString:@"isFinished"]) {
				[_offsetCalculationTextField setTextColor:(self.offsetCalculationOperation.isFinished ? [NSColor disabledControlTextColor] : [NSColor controlTextColor])];

				if(self.offsetCalculationOperation.isFinished) {
					[_possibleOffsetsArrayController addObjects:self.offsetCalculationOperation.possibleReadOffsets];
					
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
	if(!self.accurateRipQueryOperation) {
		self.accurateRipQueryOperation = [[AccurateRipQueryOperation alloc] init];
		self.accurateRipQueryOperation.compactDiscID = self.compactDisc.objectID;
		
		[self.accurateRipQueryOperation addObserver:self forKeyPath:@"isExecuting" options:0 context:kOperationQueueKVOContext];
		[self.accurateRipQueryOperation addObserver:self forKeyPath:@"isFinished" options:0 context:kOperationQueueKVOContext];
		
		[self.operationQueue addOperation:self.accurateRipQueryOperation];
	}

	// Extract a portion of the first track on the disc that is at least six seconds long
	TrackDescriptor *trackToExtract = nil;
	for(TrackDescriptor *potentialTrack in self.compactDisc.firstSession.tracks) {
		// The track must be at least six seconds long (plus the buffer); if it isn't, skip it
		if(((6 * CDDA_SECTORS_PER_SECOND) + MAXIMUM_OFFSET_TO_CHECK_IN_SECTORS) > potentialTrack.sectorCount.unsignedIntegerValue)
			continue;
		
		trackToExtract = potentialTrack;
		break;
	}
	
	if(!trackToExtract) {
		NSBeep();
		return;
	}

	SectorRange *trackSectorRange = [trackToExtract sectorRange];
	
	// AccurateRip offset checksums start at six seconds into the file
	NSUInteger sixSecondPointSector = trackSectorRange.firstSector + (6 * CDDA_SECTORS_PER_SECOND);
	
	SectorRange *sectorsToExtract = [SectorRange sectorRangeWithFirstSector:(sixSecondPointSector - MAXIMUM_OFFSET_TO_CHECK_IN_SECTORS)
																sectorCount:(2 * MAXIMUM_OFFSET_TO_CHECK_IN_SECTORS)];

	self.extractionOperation = [[ExtractionOperation alloc] init];
	
	self.extractionOperation.disk = self.disk;
	self.extractionOperation.sectors = sectorsToExtract;
	self.extractionOperation.allowedSectors = self.compactDisc.firstSession.sectorRange;
	self.extractionOperation.URL = temporaryURLWithExtension(@"wav");

	// Offset calculation
	self.offsetCalculationOperation = [[ReadOffsetCalculationOperation alloc] init];
	
	self.offsetCalculationOperation.URL = self.extractionOperation.URL;
	self.offsetCalculationOperation.trackDescriptorID = trackToExtract.objectID;
	self.offsetCalculationOperation.maximumOffsetToCheck = [NSNumber numberWithUnsignedInteger:(MAXIMUM_OFFSET_TO_CHECK_IN_SECTORS * AUDIO_FRAMES_PER_CDDA_SECTOR)];

	// Observe the operations
	[self.extractionOperation addObserver:self forKeyPath:@"isExecuting" options:0 context:kOperationQueueKVOContext];
	[self.extractionOperation addObserver:self forKeyPath:@"isFinished" options:0 context:kOperationQueueKVOContext];
	
	[self.offsetCalculationOperation addObserver:self forKeyPath:@"isExecuting" options:0 context:kOperationQueueKVOContext];
	[self.offsetCalculationOperation addObserver:self forKeyPath:@"isFinished" options:0 context:kOperationQueueKVOContext];
	
	// Set up operation dependencies
	[self.extractionOperation addDependency:self.accurateRipQueryOperation];
	[self.offsetCalculationOperation addDependency:self.extractionOperation];
	
	// Go!
	[self.operationQueue addOperation:self.extractionOperation];
	[self.operationQueue addOperation:self.offsetCalculationOperation];
}

- (IBAction) acceptSuggestedOffset:(id)sender
{
	
#pragma unused(sender)

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
	
	[[NSApplication sharedApplication] endSheet:self.window returnCode:NSOKButton];
}

- (IBAction) cancel:(id)sender
{
	
#pragma unused(sender)

	[self.operationQueue cancelAllOperations];
	
	[[NSApplication sharedApplication] endSheet:self.window returnCode:NSCancelButton];
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
	
	[[NSApplication sharedApplication] endSheet:self.window returnCode:NSOKButton];
}

@end
