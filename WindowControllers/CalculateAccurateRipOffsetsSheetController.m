/*
 *  Copyright (C) 2008 Stephen F. Booth <me@sbooth.org>
 *  All Rights Reserved
 */

#import "CalculateAccurateRipOffsetsSheetController.h"

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
static NSString * const kQueryAccurateRipKVOContext		= @"org.sbooth.Rip.DetermineAccurateRipPressingSheetController.AccurateRipQueryKVOContext";
static NSString * const kExtractAudioKVOContext			= @"org.sbooth.Rip.DetermineAccurateRipPressingSheetController.ExtractAudioKVOContext";
static NSString * const kCalculateOffsetsKVOContext		= @"org.sbooth.Rip.DetermineAccurateRipPressingSheetController.CalculateOffsetsKVOContext";

@interface CalculateAccurateRipOffsetsSheetController ()
@property (assign) CompactDisc * compactDisc;
@property (assign) DriveInformation * driveInformation;
@property (assign) NSManagedObjectContext * managedObjectContext;
@property (assign) NSOperationQueue * operationQueue;
@property (copy) NSArray * accurateRipOffsets;
@end

@interface CalculateAccurateRipOffsetsSheetController (Callbacks)
- (void) didPresentErrorWithRecovery:(BOOL)didRecover contextInfo:(void *)contextInfo;
@end

@implementation CalculateAccurateRipOffsetsSheetController

@synthesize disk = _disk;

@synthesize compactDisc = _compactDisc;
@synthesize driveInformation = _driveInformation;

@synthesize managedObjectContext = _managedObjectContext;

@synthesize operationQueue = _operationQueue;
@synthesize accurateRipOffsets = _accurateRipOffsets;

- (id) init
{
	if((self = [super initWithWindowNibName:@"CalculateAccurateRipOffsetsSheet"])) {
		// Create our own context for accessing the store
		self.managedObjectContext = [[NSManagedObjectContext alloc] init];
		[self.managedObjectContext setPersistentStoreCoordinator:[[[NSApplication sharedApplication] delegate] persistentStoreCoordinator]];
		
		self.operationQueue = [[NSOperationQueue alloc] init];
	}
	return self;
}

- (void) finalize
{
	if(_disk)
		CFRelease(_disk), _disk = NULL;
	
	[super finalize];
}

- (void) observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context
{
	if(kQueryAccurateRipKVOContext == context) {
		AccurateRipQueryOperation *operation = (AccurateRipQueryOperation *)object;
		
		if([keyPath isEqualToString:@"isExecuting"]) {
			if([operation isExecuting])
				[_statusTextField setStringValue:NSLocalizedString(@"Checking for disc in AccurateRip", @"")];
		}
		else if([keyPath isEqualToString:@"isCancelled"] || [keyPath isEqualToString:@"isFinished"]) {
			[operation removeObserver:self forKeyPath:@"isExecuting"];
			[operation removeObserver:self forKeyPath:@"isCancelled"];
			[operation removeObserver:self forKeyPath:@"isFinished"];

			if(operation.error)
				[self presentError:operation.error modalForWindow:self.window delegate:self didPresentSelector:@selector(didPresentErrorWithRecovery:contextInfo:) contextInfo:NULL];
		}
	}
	else if(kExtractAudioKVOContext == context) {
		ExtractionOperation *operation = (ExtractionOperation *)object;
		
		if([keyPath isEqualToString:@"isExecuting"]) {
			if([operation isExecuting])
				[_statusTextField setStringValue:NSLocalizedString(@"Extracting audio", @"")];
		}
		else if([keyPath isEqualToString:@"isCancelled"] || [keyPath isEqualToString:@"isFinished"]) {
			[operation removeObserver:self forKeyPath:@"isExecuting"];
			[operation removeObserver:self forKeyPath:@"isCancelled"];
			[operation removeObserver:self forKeyPath:@"isFinished"];

			if(operation.error)
				[self presentError:operation.error modalForWindow:self.window delegate:self didPresentSelector:@selector(didPresentErrorWithRecovery:contextInfo:) contextInfo:NULL];
		}
	}
	else if(kCalculateOffsetsKVOContext == context) {
		ReadOffsetCalculationOperation *operation = (ReadOffsetCalculationOperation *)object;
		
		if([keyPath isEqualToString:@"isExecuting"]) {
			if([operation isExecuting])
				[_statusTextField setStringValue:NSLocalizedString(@"Calculating possible read offsets", @"")];
		}
		else if([keyPath isEqualToString:@"isCancelled"] || [keyPath isEqualToString:@"isFinished"]) {
			[operation removeObserver:self forKeyPath:@"isExecuting"];
			[operation removeObserver:self forKeyPath:@"isCancelled"];
			[operation removeObserver:self forKeyPath:@"isFinished"];
			
			if(operation.error)
				[self presentError:operation.error modalForWindow:self.window delegate:self didPresentSelector:@selector(didPresentErrorWithRecovery:contextInfo:) contextInfo:NULL];
			else if([operation isFinished]) {
				self.accurateRipOffsets = operation.possibleReadOffsets;
				
				[_statusTextField setStringValue:[NSString stringWithFormat:NSLocalizedString(@"Detected %i possible read offsets", @""), [self.accurateRipOffsets count]]];
				[_progressIndicator stopAnimation:self];

				[[NSApplication sharedApplication] endSheet:self.window returnCode:NSOKButton];
				[self.window orderOut:self];
			}
		}
		
	}
	else
		[super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
}

#pragma mark NSWindow Delegate Methods

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

- (void) beginCalculateAccurateRipOffsetsSheetForWindow:(NSWindow *)window modalDelegate:(id)modalDelegate didEndSelector:(SEL)didEndSelector contextInfo:(void *)contextInfo
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
	
	accurateRipQueryOperation = [[AccurateRipQueryOperation alloc] init];
	accurateRipQueryOperation.compactDiscID = self.compactDisc.objectID;
	
	// Extract a portion of the first track on the disc that is at least six seconds long
	TrackDescriptor *trackToExtract = nil;
	for(TrackDescriptor *potentialTrack in self.compactDisc.firstSession.tracks) {
		// The track must be at least six seconds long (plus the buffer); if it isn't, skip it
		if(((6 * CDDA_SECTORS_PER_SECOND) + MAXIMUM_OFFSET_TO_CHECK_IN_SECTORS) > potentialTrack.sectorCount)
			continue;
		
		trackToExtract = potentialTrack;
		break;
	}
	
	if(!trackToExtract) {
		NSBeep();
		// TODO: Descriptive error message
		return;
	}
	
	SectorRange *trackSectorRange = [trackToExtract sectorRange];
	
	// AccurateRip offset checksums start at six seconds into the file
	NSUInteger sixSecondPointSector = trackSectorRange.firstSector + (6 * CDDA_SECTORS_PER_SECOND);
	
	SectorRange *sectorsToExtract = [SectorRange sectorRangeWithFirstSector:(sixSecondPointSector - MAXIMUM_OFFSET_TO_CHECK_IN_SECTORS)
																sectorCount:(2 * MAXIMUM_OFFSET_TO_CHECK_IN_SECTORS)];
	
	ExtractionOperation *extractionOperation = [[ExtractionOperation alloc] init];
	
	extractionOperation.disk = self.disk;
	extractionOperation.sectors = sectorsToExtract;
	extractionOperation.allowedSectors = self.compactDisc.firstSession.sectorRange;
	extractionOperation.readOffset = self.driveInformation.readOffset;
	extractionOperation.URL = temporaryURLWithExtension(@"wav");
	
	// Offset calculation
	ReadOffsetCalculationOperation *offsetCalculationOperation = [[ReadOffsetCalculationOperation alloc] init];
	
	offsetCalculationOperation.URL = extractionOperation.URL;
	offsetCalculationOperation.trackID = trackToExtract.objectID;
	offsetCalculationOperation.sixSecondPointSector = MAXIMUM_OFFSET_TO_CHECK_IN_SECTORS;
	offsetCalculationOperation.maximumOffsetToCheck = (MAXIMUM_OFFSET_TO_CHECK_IN_SECTORS * AUDIO_FRAMES_PER_CDDA_SECTOR);
	
	// Set up operation dependencies
	[extractionOperation addDependency:accurateRipQueryOperation];
	[offsetCalculationOperation addDependency:extractionOperation];
	
	// Observe the operations' state
	[accurateRipQueryOperation addObserver:self forKeyPath:@"isExecuting" options:NSKeyValueObservingOptionNew context:kQueryAccurateRipKVOContext];
	[accurateRipQueryOperation addObserver:self forKeyPath:@"isCancelled" options:NSKeyValueObservingOptionNew context:kQueryAccurateRipKVOContext];
	[accurateRipQueryOperation addObserver:self forKeyPath:@"isFinished" options:NSKeyValueObservingOptionNew context:kQueryAccurateRipKVOContext];
	
	[extractionOperation addObserver:self forKeyPath:@"isExecuting" options:NSKeyValueObservingOptionNew context:kExtractAudioKVOContext];
	[extractionOperation addObserver:self forKeyPath:@"isCancelled" options:NSKeyValueObservingOptionNew context:kExtractAudioKVOContext];
	[extractionOperation addObserver:self forKeyPath:@"isFinished" options:NSKeyValueObservingOptionNew context:kExtractAudioKVOContext];
	
	[offsetCalculationOperation addObserver:self forKeyPath:@"isExecuting" options:NSKeyValueObservingOptionNew context:kCalculateOffsetsKVOContext];
	[offsetCalculationOperation addObserver:self forKeyPath:@"isCancelled" options:NSKeyValueObservingOptionNew context:kCalculateOffsetsKVOContext];
	[offsetCalculationOperation addObserver:self forKeyPath:@"isFinished" options:NSKeyValueObservingOptionNew context:kCalculateOffsetsKVOContext];
	
	// Go!
	[self.operationQueue addOperation:accurateRipQueryOperation];
	[self.operationQueue addOperation:extractionOperation];
	[self.operationQueue addOperation:offsetCalculationOperation];
}

- (IBAction) cancel:(id)sender
{
	[_progressIndicator stopAnimation:sender];
	[self.operationQueue cancelAllOperations];
	
	self.disk = NULL;
	
	[[NSApplication sharedApplication] endSheet:self.window returnCode:NSCancelButton];
	[self.window orderOut:sender];
}

@end

@implementation CalculateAccurateRipOffsetsSheetController (Callbacks)

- (void) didPresentErrorWithRecovery:(BOOL)didRecover contextInfo:(void *)contextInfo
{
	
#pragma unused(contextInfo)
	
	[[NSApplication sharedApplication] endSheet:self.window returnCode:(didRecover ? NSOKButton : NSCancelButton)];	
	[self.window orderOut:self];
}

@end
