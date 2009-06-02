/*
 *  Copyright (C) 2008 - 2009 Stephen F. Booth <me@sbooth.org>
 *  All Rights Reserved
 */

#import "ExtractionViewController.h"

#import "CompactDisc.h"
#import "DriveInformation.h"

#import "SessionDescriptor.h"
#import "TrackDescriptor.h"
#import "AlbumMetadata.h"
#import "TrackMetadata.h"

#import "SectorRange.h"
#import "ExtractionOperation.h"
#import "BitArray.h"

#import "MCNDetectionOperation.h"
#import "ISRCDetectionOperation.h"
#import "PregapDetectionOperation.h"
#import "ReadOffsetCalculationOperation.h"

#import "TrackExtractionRecord.h"
#import "ImageExtractionRecord.h"

#import "AccurateRipDiscRecord.h"
#import "AccurateRipTrackRecord.h"
#import "AccurateRipUtilities.h"

#import "ReadMCNSheetController.h"
#import "ReadISRCsSheetController.h"
#import "DetectPregapsSheetController.h"

#import "EncoderManager.h"
#import "CompactDiscWindowController.h"

#import "ExtractedAudioFile.h"

#import "CDDAUtilities.h"
#import "FileUtilities.h"
#import "AudioUtilities.h"
#import "ReplayGainUtilities.h"

#import "NSIndexSet+SetMethods.h"

#import "Logger.h"

#include <AudioToolbox/AudioFile.h>

// ========================================
// Context objects for observeValueForKeyPath:ofObject:change:context:
// ========================================
static NSString * const kMCNDetectionKVOContext			= @"org.sbooth.Rip.ExtractionViewController.MCNDetectionKVOContext";
static NSString * const kISRCDetectionKVOContext		= @"org.sbooth.Rip.ExtractionViewController.ISRCDetectionKVOContext";
static NSString * const kPregapDetectionKVOContext		= @"org.sbooth.Rip.ExtractionViewController.PregapDetectionKVOContext";
static NSString * const kkAudioExtractionKVOContext		= @"org.sbooth.Rip.ExtractionViewController.ExtractAudioKVOContext";

// ========================================
// The number of sectors which will be scanned during offset verification
// ========================================
#define MAXIMUM_OFFSET_TO_CHECK_IN_SECTORS 2

// ========================================
// The minimum size (in bytes) of blocks to re-read from the disc
// ========================================
#define MINIMUM_DISC_READ_SIZE (2048 * 1024)

// For debugging
#define ENABLE_ACCURATERIP 1

// ========================================
// Secret goodness
// ========================================
@interface CompactDiscWindowController (ExtractionViewControllerMethods)
- (void) extractionFinishedWithReturnCode:(int)returnCode;
@end

@interface ExtractionViewController ()
@property (assign) CompactDisc * compactDisc;
@property (assign) DriveInformation * driveInformation;
@property (assign) NSManagedObjectContext * managedObjectContext;

@property (assign) NSOperationQueue * operationQueue;

@property (readonly) NSArray * orderedTracks;
@property (readonly) NSArray * orderedTracksRemaining;

@property (assign) NSUInteger retryCount;

@property (assign) NSTimeInterval secondsElapsed;
@property (assign) NSTimeInterval estimatedSecondsRemaining;
@property (assign) NSUInteger c2ErrorCount;
@end

// ========================================
// KVO, error presentation and NSTimer callbacks
// ========================================
@interface ExtractionViewController (Callbacks)
- (void) didPresentErrorWithRecovery:(BOOL)didRecover contextInfo:(void *)contextInfo;
- (void) audioExtractionTimerFired:(NSTimer *)timer;

- (void) detectMCNOperationDidExecute:(MCNDetectionOperation *)operation;
- (void) detectISRCOperationDidExecute:(ISRCDetectionOperation *)operation;
- (void) detectPregapOperationDidExecute:(PregapDetectionOperation *)operation;
- (void) extractionOperationDidExecute:(ExtractionOperation *)operation;
@end

// ========================================
// Methods for extracting audio off the disc
// ========================================
@interface ExtractionViewController (AudioExtraction)
- (void) extractWholeTrack:(TrackDescriptor *)track;
- (void) extractWholeTrack:(TrackDescriptor *)track useC2:(BOOL)useC2;

- (void) extractPartialTrack:(TrackDescriptor *)track sectorRange:(SectorRange *)sectorRange;
- (void) extractPartialTrack:(TrackDescriptor *)track sectorRange:(SectorRange *)sectorRange useC2:(BOOL)useC2;
- (void) extractPartialTrack:(TrackDescriptor *)track sectorRange:(SectorRange *)sectorRange useC2:(BOOL)useC2 enforceMinimumReadSize:(BOOL)enforceMinimumReadSize;
- (void) extractPartialTrack:(TrackDescriptor *)track sectorRange:(SectorRange *)sectorRange useC2:(BOOL)useC2 enforceMinimumReadSize:(BOOL)enforceMinimumReadSize cushionSectors:(NSUInteger)cushionSectors;

- (void) extractSectors:(NSIndexSet *)sectorIndexes forTrack:(TrackDescriptor *)track coalesceRanges:(BOOL)coalesceRanges;
@end

// ========================================
// Methods for creating track and image extraction records
// ========================================
@interface ExtractionViewController (ExtractionRecordCreation)
- (NSURL *) generateOutputFileForOperation:(ExtractionOperation *)operation error:(NSError **)error;

- (TrackExtractionRecord *) createTrackExtractionRecordForTrack:(TrackDescriptor *)track extractionOperation:(ExtractionOperation *)operation error:(NSError **)error;
- (TrackExtractionRecord *) createTrackExtractionRecordForTrack:(TrackDescriptor *)track extractionOperation:(ExtractionOperation *)operation accurateRipChecksum:(NSUInteger)accurateRipChecksum accurateRipConfidenceLevel:(NSNumber *)accurateRipConfidenceLevel error:(NSError **)error;
- (TrackExtractionRecord *) createTrackExtractionRecordForTrack:(TrackDescriptor *)track extractionOperation:(ExtractionOperation *)operation accurateRipChecksum:(NSUInteger)accurateRipChecksum accurateRipConfidenceLevel:(NSNumber *)accurateRipConfidenceLevel accurateRipAlternatePressingChecksum:(NSUInteger)accurateRipAlternatePressingChecksum accurateRipAlternatePressingOffset:(NSNumber *)accurateRipAlternatePressingOffset error:(NSError **)error;

- (TrackExtractionRecord *) createTrackExtractionRecordForTrack:(TrackDescriptor *)track fileURL:(NSURL *)fileURL MD5:(NSString *)MD5 SHA1:(NSString *)SHA1 accurateRipChecksum:(NSUInteger)accurateRipChecksum accurateRipConfidenceLevel:(NSNumber *)accurateRipConfidenceLevel;
- (TrackExtractionRecord *) createTrackExtractionRecordForTrack:(TrackDescriptor *)track fileURL:(NSURL *)fileURL MD5:(NSString *)MD5 SHA1:(NSString *)SHA1 accurateRipChecksum:(NSUInteger)accurateRipChecksum accurateRipConfidenceLevel:(NSNumber *)accurateRipConfidenceLevel accurateRipAlternatePressingChecksum:(NSUInteger)accurateRipAlternatePressingChecksum accurateRipAlternatePressingOffset:(NSNumber *)accurateRipAlternatePressingOffset;

- (TrackExtractionRecord *) createTrackExtractionRecordForTrack:(TrackDescriptor *)track fileURL:(NSURL *)fileURL MD5:(NSString *)MD5 SHA1:(NSString *)SHA1 blockErrorFlags:(NSIndexSet *)blockErrorFlags accurateRipChecksum:(NSUInteger)accurateRipChecksum accurateRipConfidenceLevel:(NSNumber *)accurateRipConfidenceLevel accurateRipAlternatePressingChecksum:(NSUInteger)accurateRipAlternatePressingChecksum accurateRipAlternatePressingOffset:(NSNumber *)accurateRipAlternatePressingOffset;

- (ImageExtractionRecord *) createImageExtractionRecord;
@end

// ========================================
// Encoding preparation
// ========================================
@interface ExtractionViewController (EncodingPreparation)
- (BOOL) prepareTrackForEncoding:(TrackDescriptor *)track extractionOperation:(ExtractionOperation *)operation accurateRipChecksum:(NSUInteger)accurateRipChecksum accurateRipConfidenceLevel:(NSNumber *)accurateRipConfidenceLevel error:(NSError **)error;
- (BOOL) prepareTrackForEncoding:(TrackDescriptor *)track extractionOperation:(ExtractionOperation *)operation accurateRipChecksum:(NSUInteger)accurateRipChecksum
	  accurateRipConfidenceLevel:(NSNumber *)accurateRipConfidenceLevel accurateRipAlternatePressingChecksum:(NSUInteger)accurateRipAlternatePressingChecksum accurateRipAlternatePressingOffset:(NSNumber *)accurateRipAlternatePressingOffset error:(NSError **)error;

- (BOOL) prepareTrackForEncoding:(TrackDescriptor *)track fileURL:(NSURL *)fileURL MD5:(NSString *)MD5 SHA1:(NSString *)SHA1 accurateRipChecksum:(NSUInteger)accurateRipChecksum accurateRipConfidenceLevel:(NSNumber *)accurateRipConfidenceLevel;
- (BOOL) prepareTrackForEncoding:(TrackDescriptor *)track fileURL:(NSURL *)fileURL MD5:(NSString *)MD5 SHA1:(NSString *)SHA1 accurateRipChecksum:(NSUInteger)accurateRipChecksum accurateRipConfidenceLevel:(NSNumber *)accurateRipConfidenceLevel accurateRipAlternatePressingChecksum:(NSUInteger)accurateRipAlternatePressingChecksum accurateRipAlternatePressingOffset:(NSNumber *)accurateRipAlternatePressingOffset;

- (void) addTrackExtractionRecord:(TrackExtractionRecord *)extractionRecord;
@end

// ========================================
// AccurateRip support
// ========================================
@interface ExtractionViewController (AccurateRip)
- (NSUInteger) calculateAccurateRipChecksumForTrack:(TrackDescriptor *)track extractionOperation:(ExtractionOperation *)operation;
- (NSUInteger) calculateAccurateRipChecksumForTrack:(TrackDescriptor *)track extractionOperation:(ExtractionOperation *)operation readOffsetAdjustment:(NSUInteger)readOffsetAdjustment;

- (NSArray *) determinePossibleAccurateRipOffsetForTrack:(TrackDescriptor *)track URL:(NSURL *)URL;
- (NSArray *) determinePossibleAccurateRipOffsetForTrack:(TrackDescriptor *)track URL:(NSURL *)URL startingSector:(NSUInteger)startingSector;
@end

// ========================================
// The real work is done here
// ========================================
@interface ExtractionViewController (Private)
- (void) removeTemporaryFiles;
- (void) resetExtractionState;

- (void) startExtractingNextTrack;

- (void) processExtractionOperation:(ExtractionOperation *)operation;
- (void) processExtractionOperation:(ExtractionOperation *)operation forWholeTrack:(TrackDescriptor *)track;
- (void) processExtractionOperation:(ExtractionOperation *)operation forPartialTrack:(TrackDescriptor *)track;

- (NSData *) dataForSector:(NSUInteger)sector interpolate:(BOOL)interpolate;
- (NSData *) dataForSector:(NSUInteger)sector interpolate:(BOOL)interpolate useC2:(BOOL)useC2;

- (NSData *) nonInterpolatedDataForSector:(NSUInteger)sector;
- (NSData *) nonInterpolatedDataForSector:(NSUInteger)sector useC2:(BOOL)useC2;

- (NSData *) interpolatedDataForSector:(NSUInteger)sector;
- (NSData *) interpolatedDataForSector:(NSUInteger)sector useC2:(BOOL)useC2;

- (NSIndexSet *) mismatchedSectorsForTrack:(TrackDescriptor *)track;
- (NSIndexSet *) mismatchedSectorsForTrack:(TrackDescriptor *)track useC2:(BOOL)useC2;

- (NSURL *) outputURLForTrack:(TrackDescriptor *)track;
- (NSURL *) outputURLForTrack:(TrackDescriptor *)track useC2:(BOOL)useC2;

- (BOOL) saveSector:(NSUInteger)sector sectorData:(NSData *)sectorData forTrack:(TrackDescriptor *)track;
- (BOOL) saveSectors:(NSIndexSet *)sectors fromOperation:(ExtractionOperation *)operation forTrack:(TrackDescriptor *)track;
@end

@implementation ExtractionViewController

@synthesize disk = _disk;
@synthesize trackIDs = _trackIDs;

@synthesize maxRetries = _maxRetries;
@synthesize requiredSectorMatches = _requiredSectorMatches;
@synthesize requiredTrackMatches = _requiredTrackMatches;
@synthesize extractionMode = _extractionMode;

@synthesize imageExtractionRecord = _imageExtractionRecord;
@synthesize trackExtractionRecords = _trackExtractionRecords;
@synthesize failedTrackIDs = _failedTrackIDs;

@synthesize secondsElapsed = _secondsElapsed;
@synthesize estimatedSecondsRemaining = _estimatedSecondsRemaining;
@synthesize c2ErrorCount = _c2ErrorCount;

@synthesize compactDisc = _compactDisc;
@synthesize driveInformation = _driveInformation;
@synthesize managedObjectContext = _managedObjectContext;

@synthesize operationQueue = _operationQueue;

@synthesize retryCount = _retryCount;

- (id) init
{
	if((self = [super initWithNibName:@"ExtractionView" bundle:nil])) {
		// Create our own context for accessing the store
		self.managedObjectContext = [[NSManagedObjectContext alloc] init];
		[self.managedObjectContext setPersistentStoreCoordinator:[[[NSApplication sharedApplication] delegate] persistentStoreCoordinator]];
		
		// Register to receive NSManagedObjectContextDidSaveNotification to keep our MOC in sync
		[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(managedObjectContextDidSave:) name:NSManagedObjectContextDidSaveNotification object:nil];

		self.operationQueue = [[NSOperationQueue alloc] init];
		[self.operationQueue setMaxConcurrentOperationCount:1];
		
		_activeTimers = [NSMutableArray array];
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
	NSSortDescriptor *trackNumberSortDescriptor = [[NSSortDescriptor alloc] initWithKey:@"number" ascending:YES];
	[_tracksArrayController setSortDescriptors:[NSArray arrayWithObject:trackNumberSortDescriptor]];
}

- (void) observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context
{
	if(kMCNDetectionKVOContext == context) {
		MCNDetectionOperation *operation = (MCNDetectionOperation *)object;
		
		if([keyPath isEqualToString:@"isExecuting"]) {			
			if([operation isExecuting]) {
				// KVO is thread-safe, but doesn't guarantee observeValueForKeyPath: will be called from the main thread
				if([NSThread isMainThread])
					[self detectMCNOperationDidExecute:operation];
				else
					[self performSelectorOnMainThread:@selector(detectMCNOperationDidExecute:) withObject:operation waitUntilDone:NO];
			}
		}
		else if([keyPath isEqualToString:@"isCancelled"] || [keyPath isEqualToString:@"isFinished"]) {
			[operation removeObserver:self forKeyPath:@"isExecuting"];
			[operation removeObserver:self forKeyPath:@"isCancelled"];
			[operation removeObserver:self forKeyPath:@"isFinished"];
		}
	}
	else if(kISRCDetectionKVOContext == context) {
		ISRCDetectionOperation *operation = (ISRCDetectionOperation *)object;
		
		if([keyPath isEqualToString:@"isExecuting"]) {
			if([operation isExecuting]) {
				// KVO is thread-safe, but doesn't guarantee observeValueForKeyPath: will be called from the main thread
				if([NSThread isMainThread])
					[self detectISRCOperationDidExecute:operation];
				else
					[self performSelectorOnMainThread:@selector(detectISRCOperationDidExecute:) withObject:operation waitUntilDone:NO];
			}
		}
		else if([keyPath isEqualToString:@"isCancelled"] || [keyPath isEqualToString:@"isFinished"]) {
			[operation removeObserver:self forKeyPath:@"isExecuting"];
			[operation removeObserver:self forKeyPath:@"isCancelled"];
			[operation removeObserver:self forKeyPath:@"isFinished"];
		}
	}
	else if(kPregapDetectionKVOContext == context) {
		PregapDetectionOperation *operation = (PregapDetectionOperation *)object;
		
		if([keyPath isEqualToString:@"isExecuting"]) {
			if([operation isExecuting]) {
				// KVO is thread-safe, but doesn't guarantee observeValueForKeyPath: will be called from the main thread
				if([NSThread isMainThread])
					[self detectPregapOperationDidExecute:operation];
				else
					[self performSelectorOnMainThread:@selector(detectPregapOperationDidExecute:) withObject:operation waitUntilDone:NO];
			}
		}
		else if([keyPath isEqualToString:@"isCancelled"] || [keyPath isEqualToString:@"isFinished"]) {
			[operation removeObserver:self forKeyPath:@"isExecuting"];
			[operation removeObserver:self forKeyPath:@"isCancelled"];
			[operation removeObserver:self forKeyPath:@"isFinished"];
		}
	}
	else if(kkAudioExtractionKVOContext == context) {
		ExtractionOperation *operation = (ExtractionOperation *)object;
		
		if([keyPath isEqualToString:@"isExecuting"]) {
			if([operation isExecuting]) {
				// Schedule a timer which will update the UI while the operations runs
				NSTimer *timer = [NSTimer timerWithTimeInterval:(1.0 / 3.0) target:self selector:@selector(audioExtractionTimerFired:) userInfo:operation repeats:YES];
				[[NSRunLoop mainRunLoop] addTimer:timer forMode:NSRunLoopCommonModes];
				[_activeTimers addObject:timer];
				
				// KVO is thread-safe, but doesn't guarantee observeValueForKeyPath: will be called from the main thread
				if([NSThread isMainThread])
					[self extractionOperationDidExecute:operation];
				else
					[self performSelectorOnMainThread:@selector(extractionOperationDidExecute:) withObject:operation waitUntilDone:NO];
			}
		}
		else if([keyPath isEqualToString:@"isCancelled"] || [keyPath isEqualToString:@"isFinished"]) {
			[operation removeObserver:self forKeyPath:@"isExecuting"];
			[operation removeObserver:self forKeyPath:@"isCancelled"];
			[operation removeObserver:self forKeyPath:@"isFinished"];
			
			// Process the extracted audio
			// KVO is thread-safe, but doesn't guarantee observeValueForKeyPath: will be called from the main thread
			if([NSThread isMainThread])
				[self processExtractionOperation:operation];
			else
				[self performSelectorOnMainThread:@selector(processExtractionOperation:) withObject:operation waitUntilDone:NO];
		}
	}	
	else
		[super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
}

- (BOOL) validateMenuItem:(NSMenuItem *)menuItem
{
	if([menuItem action] == @selector(cancel:)) {
		[menuItem setTitle:NSLocalizedString(@"Cancel Extraction", @"")];
		return (0 != [[_operationQueue operations] count]);
	}
	else if([self respondsToSelector:[menuItem action]])
		return YES;
	else
		return NO;
}

- (void) managedObjectContextDidSave:(NSNotification *)notification
{
	NSParameterAssert(nil != notification);
	
	// "Auto-refresh" objects changed in another MOC
	NSManagedObjectContext *managedObjectContext = [notification object];
	if(managedObjectContext != self.managedObjectContext)
		[self.managedObjectContext mergeChangesFromContextDidSaveNotification:notification];
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

- (IBAction) extract:(id)sender
{

#pragma unused(sender)
	
	// Copy the array containing the tracks to be extracted
	_trackIDsRemaining = [self.trackIDs mutableCopy];
	
	// Set up the extraction records
	_trackExtractionRecords = [NSMutableSet set];
	_failedTrackIDs = [NSMutableSet set];
	
	[self willChangeValueForKey:@"tracks"];
	_tracks = [NSSet setWithArray:self.orderedTracks];
	[self didChangeValueForKey:@"tracks"];
	
	// Init replay gain
	int result = replaygain_analysis_init(&_rg, CDDA_SAMPLE_RATE);
	if(INIT_GAIN_ANALYSIS_OK != result)
		[[Logger sharedLogger] logMessage:NSLocalizedString(@"Unable to initialize replay gain", @"")];
	
	// Before starting extraction, ensure the disc's MCN has been read
	if(!self.compactDisc.metadata.MCN) {
		MCNDetectionOperation *operation = [[MCNDetectionOperation alloc] init];
		
		operation.disk = self.disk;
		
		[operation addObserver:self forKeyPath:@"isExecuting" options:NSKeyValueObservingOptionNew context:kMCNDetectionKVOContext];
		[operation addObserver:self forKeyPath:@"isFinished" options:NSKeyValueObservingOptionNew context:kMCNDetectionKVOContext];
		[operation addObserver:self forKeyPath:@"isCancelled" options:NSKeyValueObservingOptionNew context:kMCNDetectionKVOContext];
		
		[self.operationQueue addOperation:operation];
	}
	
	// Get started on the first one
	[self startExtractingNextTrack];
}

- (IBAction) skipTrack:(id)sender
{
	NSLog(@"skipTrack: %@",sender);
}

- (IBAction) cancel:(id)sender
{

#pragma unused(sender)

	[self.operationQueue cancelAllOperations];
	
	// Remove any active timers
	[_activeTimers makeObjectsPerformSelector:@selector(invalidate)];
	[_activeTimers removeAllObjects];
	
	// Remove temporary files
	[self removeTemporaryFiles];	
	
	self.disk = NULL;

	[[[[self view] window] windowController] extractionFinishedWithReturnCode:NSCancelButton];
}

- (NSArray *) orderedTracks
{
	// Fetch the tracks to be extracted and sort them by track number
	NSPredicate *trackPredicate  = [NSPredicate predicateWithFormat:@"self IN %@", self.trackIDs];
	NSSortDescriptor *trackNumberSortDescriptor = [[NSSortDescriptor alloc] initWithKey:@"number" ascending:YES];
	NSEntityDescription *trackEntityDescription = [NSEntityDescription entityForName:@"TrackDescriptor" inManagedObjectContext:self.managedObjectContext];
	
	NSFetchRequest *trackFetchRequest = [[NSFetchRequest alloc] init];
	
	[trackFetchRequest setEntity:trackEntityDescription];
	[trackFetchRequest setPredicate:trackPredicate];
	[trackFetchRequest setSortDescriptors:[NSArray arrayWithObject:trackNumberSortDescriptor]];
	
	NSError *error = nil;
	NSArray *tracks = [self.managedObjectContext executeFetchRequest:trackFetchRequest error:&error];
	if(!tracks) {
		[self presentError:error modalForWindow:[[self view] window] delegate:self didPresentSelector:@selector(didPresentErrorWithRecovery:contextInfo:) contextInfo:NULL];
		return nil;
	}
	
	return tracks;
}

- (NSArray *) orderedTracksRemaining
{
	// Fetch the tracks to be extracted and sort them by track number
	NSPredicate *trackPredicate  = [NSPredicate predicateWithFormat:@"self IN %@", _trackIDsRemaining];
	NSSortDescriptor *trackNumberSortDescriptor = [[NSSortDescriptor alloc] initWithKey:@"number" ascending:YES];
	NSEntityDescription *trackEntityDescription = [NSEntityDescription entityForName:@"TrackDescriptor" inManagedObjectContext:self.managedObjectContext];
	
	NSFetchRequest *trackFetchRequest = [[NSFetchRequest alloc] init];
	
	[trackFetchRequest setEntity:trackEntityDescription];
	[trackFetchRequest setPredicate:trackPredicate];
	[trackFetchRequest setSortDescriptors:[NSArray arrayWithObject:trackNumberSortDescriptor]];
	
	NSError *error = nil;
	NSArray *tracks = [self.managedObjectContext executeFetchRequest:trackFetchRequest error:&error];
	if(!tracks) {
		[self presentError:error modalForWindow:[[self view] window] delegate:self didPresentSelector:@selector(didPresentErrorWithRecovery:contextInfo:) contextInfo:NULL];
		return nil;
	}
	
	return tracks;
}

#pragma mark NSTableView Delegate Methods

- (void)tableView:(NSTableView *)tableView willDisplayCell:(id)cell forTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row
{
	if(tableView == _tracksTable) {
		NSString *columnIdentifier = tableColumn.identifier;
		
		TrackDescriptor *track = [[_tracksArrayController arrangedObjects] objectAtIndex:row];
		NSManagedObjectID *trackID = track.objectID;

		if([columnIdentifier isEqualToString:@"status"]) {
			// Tracks which have failed should be highlighted in red
			if([_failedTrackIDs containsObject:trackID]) {
//				NSColor *failureColor = [NSColor redColor];
//				NSDictionary *attributes = [NSDictionary dictionaryWithObject:failureColor forKey:NSForegroundColorAttributeName];
//				NSAttributedString *attributedString = [[NSAttributedString alloc] initWithString:NSLocalizedString(@"Extraction failed", @"") attributes:attributes];
//				[cell setAttributedStringValue:attributedString];

				[cell setStringValue:NSLocalizedString(@"Extraction failed", @"")];
				[cell setImage:[NSImage imageNamed:@"Red X"]];
			}
			// Success will be in green
			else if([[_trackExtractionRecords valueForKeyPath:@"track.objectID"] containsObject:trackID]) {
				NSSet *matchingTrackExtractionRecords = [_trackExtractionRecords filteredSetUsingPredicate:[NSPredicate predicateWithFormat:@"track.objectID == %@", trackID]];
				if(![matchingTrackExtractionRecords count])
					return;
				TrackExtractionRecord *extractionRecord = [matchingTrackExtractionRecords anyObject];
				NSNumber *accurateRipConfidenceLevel = extractionRecord.accurateRipConfidenceLevel;
				NSString *description = nil;
				if([accurateRipConfidenceLevel unsignedIntegerValue])
					description = [NSString stringWithFormat:NSLocalizedString(@"Accurate (%@)", @""), accurateRipConfidenceLevel];
				else
					description = NSLocalizedString(@"Copy Verified", @"");

//				NSColor *successColor = [NSColor colorWithDeviceRed:0 green:(116.0f / 255.0f) blue:0 alpha:1.0f];
//				NSDictionary *attributes = [NSDictionary dictionaryWithObject:successColor forKey:NSForegroundColorAttributeName];
//				NSAttributedString *attributedString = [[NSAttributedString alloc] initWithString:description attributes:attributes];
//				[cell setAttributedStringValue:attributedString];
				
				[cell setStringValue:description];
				[cell setImage:[NSImage imageNamed:@"Green Check"]];
			}
			// Processing will be the standard color
			else if([[_currentTrack objectID] isEqual:trackID]) {
				[cell setStringValue:NSLocalizedString(@"In Progress", @"")];
				[cell setImage:nil];
			}
			// And queued should be in black with one-third alpha
			else {
				NSColor *queuedColor = [[NSColor blackColor] colorWithAlphaComponent:(1.0f / 3.0f)];
				NSDictionary *attributes = [NSDictionary dictionaryWithObject:queuedColor forKey:NSForegroundColorAttributeName];
				NSAttributedString *attributedString = [[NSAttributedString alloc] initWithString:NSLocalizedString(@"Queued", @"") attributes:attributes];
				
				[cell setAttributedStringValue:attributedString];
				[cell setImage:nil];
			}
		}
	}
}

@end

@implementation ExtractionViewController (Callbacks)

- (void) didPresentErrorWithRecovery:(BOOL)didRecover contextInfo:(void *)contextInfo
{
	
#pragma unused(contextInfo)
	
	[self removeTemporaryFiles];
	
	// Remove any active timers
	[_activeTimers makeObjectsPerformSelector:@selector(invalidate)];
	[_activeTimers removeAllObjects];
	
	self.disk = NULL;
	
	[[[[self view] window] windowController] extractionFinishedWithReturnCode:(didRecover ? NSOKButton : NSCancelButton)];
}

- (void) audioExtractionTimerFired:(NSTimer *)timer
{
	ExtractionOperation *operation = (ExtractionOperation *)[timer userInfo];
	
	if([operation isFinished] || [operation isCancelled]) {
		[_activeTimers removeObjectIdenticalTo:timer];
		[timer invalidate];
		return;
	}
	
	[_progressIndicator setDoubleValue:operation.fractionComplete];
	
	NSTimeInterval secondsElapsed = [[NSDate date] timeIntervalSinceDate:operation.startTime];
	
	self.secondsElapsed = secondsElapsed;
	self.estimatedSecondsRemaining = (secondsElapsed / operation.fractionComplete) - secondsElapsed;
	self.c2ErrorCount = [operation.errorFlags count];
}

- (void) detectMCNOperationDidExecute:(MCNDetectionOperation *)operation
{
	
#pragma unused(operation)
	
	[_progressIndicator setIndeterminate:YES];
	[_progressIndicator startAnimation:self];
	
	NSString *discDescription = nil;
	if(self.compactDisc.metadata.title)
		discDescription = self.compactDisc.metadata.title;
	else
		discDescription = self.compactDisc.musicBrainzDiscID;
	
	[_statusTextField setStringValue:discDescription];
	[_detailedStatusTextField setStringValue:NSLocalizedString(@"Reading the disc's Media Catalog Number", @"")];
}

- (void) detectISRCOperationDidExecute:(ISRCDetectionOperation *)operation
{
	[_progressIndicator setIndeterminate:YES];
	[_progressIndicator startAnimation:self];
	
	// Fetch the TrackDescriptor object from the context and ensure it is the correct class
	NSManagedObject *managedObject = [self.managedObjectContext objectWithID:operation.trackID];
	if(![managedObject isKindOfClass:[TrackDescriptor class]])
		return;
	
	TrackDescriptor *track = (TrackDescriptor *)managedObject;
	
	NSString *trackDescription = nil;
	if(track.metadata.title)
		trackDescription = track.metadata.title;
	else
		trackDescription = [track.number stringValue];
	
	[_detailedStatusTextField setStringValue:NSLocalizedString(@"Reading the International Standard Recording Code", @"")];
	[_statusTextField setStringValue:trackDescription];
}

- (void) detectPregapOperationDidExecute:(PregapDetectionOperation *)operation
{
	[_progressIndicator setIndeterminate:YES];
	[_progressIndicator startAnimation:self];
	
	// Fetch the TrackDescriptor object from the context and ensure it is the correct class
	NSManagedObject *managedObject = [self.managedObjectContext objectWithID:operation.trackID];
	if(![managedObject isKindOfClass:[TrackDescriptor class]])
		return;
	
	TrackDescriptor *track = (TrackDescriptor *)managedObject;
	
	NSString *trackDescription = nil;
	if(track.metadata.title)
		trackDescription = track.metadata.title;
	else
		trackDescription = [track.number stringValue];
	
	[_detailedStatusTextField setStringValue:NSLocalizedString(@"Detecting the pregap", @"")];
	[_statusTextField setStringValue:trackDescription];
}

- (void) extractionOperationDidExecute:(ExtractionOperation *)operation
{
	NSParameterAssert(nil != operation);
	
	[_progressIndicator setIndeterminate:NO];
	[_progressIndicator setMinValue:0.0];
	[_progressIndicator setMaxValue:1.0];
	[_progressIndicator setDoubleValue:0.0];
	
	if(operation.trackID) {
		// Fetch the TrackDescriptor object from the context and ensure it is the correct class
		NSManagedObject *managedObject = [self.managedObjectContext objectWithID:operation.trackID];
		if(![managedObject isKindOfClass:[TrackDescriptor class]])
			return;
		
		TrackDescriptor *track = (TrackDescriptor *)managedObject;				
		
		// Create a user-friendly representation of the track being processed
		if(track.metadata.title)
			[_statusTextField setStringValue:track.metadata.title];
		else
			[_statusTextField setStringValue:[track.number stringValue]];
		
		// Determine if this operation represents a whole track extraction or a partial track extraction
		BOOL isWholeTrack = [operation.sectors containsSectorRange:track.sectorRange];
		
		// Check to see if this track has been extracted before
		if(!isWholeTrack)
			[_detailedStatusTextField setStringValue:[NSString stringWithFormat:NSLocalizedString(@"Re-extracting sectors %ld - %ld", @""), operation.sectors.firstSector, operation.sectors.lastSector]];
		else if([_wholeExtractions count])
			[_detailedStatusTextField setStringValue:NSLocalizedString(@"Re-extracting audio", @"")];
		else
			[_detailedStatusTextField setStringValue:NSLocalizedString(@"Extracting audio", @"")];
	}
	else
		[_detailedStatusTextField setStringValue:NSLocalizedString(@"Unknown", @"")];
}

@end


@implementation ExtractionViewController (AudioExtraction)

- (void) extractWholeTrack:(TrackDescriptor *)track
{
	[self extractWholeTrack:track useC2:[self.driveInformation.useC2 boolValue]];
}

- (void) extractWholeTrack:(TrackDescriptor *)track useC2:(BOOL)useC2
{
	[self extractPartialTrack:track sectorRange:track.sectorRange useC2:useC2 enforceMinimumReadSize:NO cushionSectors:MAXIMUM_OFFSET_TO_CHECK_IN_SECTORS];
}

- (void) extractPartialTrack:(TrackDescriptor *)track sectorRange:(SectorRange *)sectorRange
{
	[self extractPartialTrack:track sectorRange:sectorRange useC2:[self.driveInformation.useC2 boolValue] enforceMinimumReadSize:NO cushionSectors:0];
}

- (void) extractPartialTrack:(TrackDescriptor *)track sectorRange:(SectorRange *)sectorRange useC2:(BOOL)useC2
{
	[self extractPartialTrack:track sectorRange:sectorRange useC2:useC2 enforceMinimumReadSize:NO cushionSectors:0];
}

- (void) extractPartialTrack:(TrackDescriptor *)track sectorRange:(SectorRange *)sectorRange useC2:(BOOL)useC2 enforceMinimumReadSize:(BOOL)enforceMinimumReadSize
{
	[self extractPartialTrack:track sectorRange:sectorRange useC2:useC2 enforceMinimumReadSize:enforceMinimumReadSize cushionSectors:0];
}

- (void) extractPartialTrack:(TrackDescriptor *)track sectorRange:(SectorRange *)sectorRange useC2:(BOOL)useC2 enforceMinimumReadSize:(BOOL)enforceMinimumReadSize cushionSectors:(NSUInteger)cushionSectors
{
	NSParameterAssert(nil != track);
	NSParameterAssert(nil != sectorRange);
	
	// Should a block of at least MINIMUM_DISC_READ_SIZE be read?
	if(enforceMinimumReadSize && MINIMUM_DISC_READ_SIZE > sectorRange.byteSize) {
		NSUInteger sizeIncrease = MINIMUM_DISC_READ_SIZE - sectorRange.byteSize;
		NSUInteger sectorOffset = ((sizeIncrease / 2)  / kCDSectorSizeCDDA) + 1;
		
		NSUInteger newFirstSector = sectorRange.firstSector;
		if(newFirstSector > sectorOffset)
			newFirstSector -= sectorOffset;
		NSUInteger newLastSector = sectorRange.lastSector + sectorOffset;
		
		sectorRange = [SectorRange sectorRangeWithFirstSector:newFirstSector lastSector:newLastSector];
	}
	
	// Audio extraction
	ExtractionOperation *extractionOperation = [[ExtractionOperation alloc] init];
	
	extractionOperation.disk = self.disk;
	extractionOperation.sectors = sectorRange;
	extractionOperation.allowedSectors = self.compactDisc.firstSession.sectorRange;
	extractionOperation.cushionSectors = cushionSectors;
	extractionOperation.trackID = [track objectID];
	extractionOperation.readOffset = self.driveInformation.readOffset;
	extractionOperation.URL = temporaryURLWithExtension(@"wav");
	extractionOperation.useC2 = useC2;
	
	// Observe the operation's progress
	[extractionOperation addObserver:self forKeyPath:@"isExecuting" options:NSKeyValueObservingOptionNew context:kkAudioExtractionKVOContext];
	[extractionOperation addObserver:self forKeyPath:@"isCancelled" options:NSKeyValueObservingOptionNew context:kkAudioExtractionKVOContext];
	[extractionOperation addObserver:self forKeyPath:@"isFinished" options:NSKeyValueObservingOptionNew context:kkAudioExtractionKVOContext];
	
	// Do it.  Do it.  Do it.
	[self.operationQueue addOperation:extractionOperation];
}

- (void) extractSectors:(NSIndexSet *)sectorIndexes forTrack:(TrackDescriptor *)track coalesceRanges:(BOOL)coalesceRanges
{
	NSParameterAssert(nil != track);
	NSParameterAssert(nil != sectorIndexes);
	
	// Coalesce the index set into ranges to minimize the number of disc accesses
	if(coalesceRanges) {
		NSUInteger firstIndex = NSNotFound;
		NSUInteger latestIndex = NSNotFound;
		NSUInteger sectorIndex = [sectorIndexes firstIndex];
		
		for(;;) {
			// Last sector
			if(NSNotFound == sectorIndex) {
				if(NSNotFound != firstIndex) {
					if(firstIndex == latestIndex)
						[self extractPartialTrack:track sectorRange:[SectorRange sectorRangeWithSector:firstIndex] useC2:[self.driveInformation.useC2 boolValue] enforceMinimumReadSize:YES];
					else
						[self extractPartialTrack:track sectorRange:[SectorRange sectorRangeWithFirstSector:firstIndex lastSector:latestIndex] useC2:[self.driveInformation.useC2 boolValue] enforceMinimumReadSize:YES];
				}
				
				break;
			}
			
			// Consolidate this sector into the current range
			if(latestIndex == (sectorIndex - 1))
				latestIndex = sectorIndex;
			// Store the previous range and start a new one
			else {
				if(NSNotFound != firstIndex) {
					if(firstIndex == latestIndex)
						[self extractPartialTrack:track sectorRange:[SectorRange sectorRangeWithSector:firstIndex] useC2:[self.driveInformation.useC2 boolValue] enforceMinimumReadSize:YES];
					else
						[self extractPartialTrack:track sectorRange:[SectorRange sectorRangeWithFirstSector:firstIndex lastSector:latestIndex] useC2:[self.driveInformation.useC2 boolValue] enforceMinimumReadSize:YES];
				}
				
				firstIndex = sectorIndex;
				latestIndex = sectorIndex;
			}
			
			sectorIndex = [sectorIndexes indexGreaterThanIndex:sectorIndex];
		}
	}
	else {
		NSUInteger sectorIndex = [sectorIndexes firstIndex];
		while(NSNotFound != sectorIndex) {
			[self extractPartialTrack:track sectorRange:[SectorRange sectorRangeWithSector:sectorIndex] useC2:[self.driveInformation.useC2 boolValue] enforceMinimumReadSize:YES];
			sectorIndex = [sectorIndexes indexGreaterThanIndex:sectorIndex];			
		}
		
	}	
}

@end


@implementation ExtractionViewController (ExtractionRecordCreation)

- (NSURL *) generateOutputFileForOperation:(ExtractionOperation *)operation error:(NSError **)error
{
	NSParameterAssert(nil != operation);
	
	[_detailedStatusTextField setStringValue:NSLocalizedString(@"Creating output file", @"")];	
	
	NSURL *URL = operation.URL;
	
	// Strip off the cushion sectors before encoding, if present
	if(operation.cushionSectors) {
		ExtractedAudioFile *inputFile = [ExtractedAudioFile openFileForReadingAtURL:operation.URL error:error];
		
		if(!inputFile)
			return nil;
		
		ExtractedAudioFile *outputFile = [ExtractedAudioFile createFileAtURL:temporaryURLWithExtension(@"wav") error:error];
		
		if(!outputFile) {
			[inputFile closeFile], inputFile = nil;
			return nil;
		}
		
		int8_t buffer [kCDSectorSizeCDDA];
		NSUInteger startingSector = operation.cushionSectors;
		NSUInteger sectorCount = operation.sectors.length;
		NSUInteger sectorCounter = 0;
		
		// Copy sectors from the input file to the output file, one sector at a time
		while(sectorCounter < sectorCount) {
			NSUInteger sectorsRead = [inputFile readAudioForSectors:NSMakeRange(startingSector, 1) buffer:buffer error:error];
			
			if(0 == sectorsRead) {
				[inputFile closeFile], inputFile = nil;
				[outputFile closeFile], outputFile = nil;
				return nil;
			}
			
			NSUInteger sectorsWritten = [outputFile setAudio:buffer forSectors:NSMakeRange(sectorCounter, 1) error:error];
			
			if(0 == sectorsWritten) {
				[inputFile closeFile], inputFile = nil;
				[outputFile closeFile], outputFile = nil;
				return nil;
			}
			
			++sectorCounter;
			++startingSector;
		}
		
		// Sanity check to ensure the correct sectors were removed and all sectors were copied
		if(![operation.MD5 isEqualToString:outputFile.MD5] || ![operation.SHA1 isEqualToString:outputFile.SHA1]) {
			[[Logger sharedLogger] logMessage:@"Internal inconsistency: MD5 or SHA1 for extracted and synthesized audio don't match"];
			
			[inputFile closeFile], inputFile = nil;
			[outputFile closeFile], outputFile = nil;
			
			if(error)
				*error = [NSError errorWithDomain:NSCocoaErrorDomain code:42 userInfo:nil];
			return nil;
		}
		
		URL = outputFile.URL;
		
		[inputFile closeFile], inputFile = nil;
		[outputFile closeFile], outputFile = nil;
	}
	
	return URL;
}

- (TrackExtractionRecord *) createTrackExtractionRecordForTrack:(TrackDescriptor *)track 
											extractionOperation:(ExtractionOperation *)operation
														  error:(NSError **)error
{
	return [self createTrackExtractionRecordForTrack:track
								 extractionOperation:operation
								 accurateRipChecksum:0
						  accurateRipConfidenceLevel:nil
											   error:error];
}

- (TrackExtractionRecord *) createTrackExtractionRecordForTrack:(TrackDescriptor *)track
											extractionOperation:(ExtractionOperation *)operation
											accurateRipChecksum:(NSUInteger)accurateRipChecksum
									 accurateRipConfidenceLevel:(NSNumber *)accurateRipConfidenceLevel
														  error:(NSError **)error
{
	return [self createTrackExtractionRecordForTrack:track
								 extractionOperation:operation
								 accurateRipChecksum:accurateRipChecksum
						  accurateRipConfidenceLevel:accurateRipConfidenceLevel
				accurateRipAlternatePressingChecksum:0
				  accurateRipAlternatePressingOffset:nil
											   error:error];
}

- (TrackExtractionRecord *) createTrackExtractionRecordForTrack:(TrackDescriptor *)track
											extractionOperation:(ExtractionOperation *)operation
											accurateRipChecksum:(NSUInteger)accurateRipChecksum
									 accurateRipConfidenceLevel:(NSNumber *)accurateRipConfidenceLevel
						   accurateRipAlternatePressingChecksum:(NSUInteger)accurateRipAlternatePressingChecksum
							 accurateRipAlternatePressingOffset:(NSNumber *)accurateRipAlternatePressingOffset
														  error:(NSError **)error
{
	// Create the output file, if required
	NSURL *fileURL = [self generateOutputFileForOperation:operation error:error];
	if(nil == fileURL)
		return nil;
	
	return [self createTrackExtractionRecordForTrack:track
											 fileURL:fileURL
												 MD5:operation.MD5
												SHA1:operation.SHA1
									 blockErrorFlags:operation.blockErrorFlags
								 accurateRipChecksum:accurateRipChecksum
						  accurateRipConfidenceLevel:accurateRipConfidenceLevel
				accurateRipAlternatePressingChecksum:accurateRipAlternatePressingChecksum
				  accurateRipAlternatePressingOffset:accurateRipAlternatePressingOffset];
}

- (TrackExtractionRecord *) createTrackExtractionRecordForTrack:(TrackDescriptor *)track 
														fileURL:(NSURL *)fileURL
															MD5:(NSString *)MD5
														   SHA1:(NSString *)SHA1
											accurateRipChecksum:(NSUInteger)accurateRipChecksum
									 accurateRipConfidenceLevel:(NSNumber *)accurateRipConfidenceLevel
{
	return [self createTrackExtractionRecordForTrack:track
											 fileURL:fileURL
												 MD5:MD5
												SHA1:SHA1
									 blockErrorFlags:nil
								 accurateRipChecksum:accurateRipChecksum
						  accurateRipConfidenceLevel:accurateRipConfidenceLevel
				accurateRipAlternatePressingChecksum:0
				  accurateRipAlternatePressingOffset:nil];
}

- (TrackExtractionRecord *) createTrackExtractionRecordForTrack:(TrackDescriptor *)track 
														fileURL:(NSURL *)fileURL
															MD5:(NSString *)MD5
														   SHA1:(NSString *)SHA1
											accurateRipChecksum:(NSUInteger)accurateRipChecksum
									 accurateRipConfidenceLevel:(NSNumber *)accurateRipConfidenceLevel
						   accurateRipAlternatePressingChecksum:(NSUInteger)accurateRipAlternatePressingChecksum
							 accurateRipAlternatePressingOffset:(NSNumber *)accurateRipAlternatePressingOffset
{
	return [self createTrackExtractionRecordForTrack:track
											 fileURL:fileURL
												 MD5:MD5
												SHA1:SHA1
									 blockErrorFlags:nil
								 accurateRipChecksum:accurateRipChecksum
						  accurateRipConfidenceLevel:accurateRipConfidenceLevel
				accurateRipAlternatePressingChecksum:accurateRipAlternatePressingChecksum
				  accurateRipAlternatePressingOffset:accurateRipAlternatePressingOffset];
}
	
- (TrackExtractionRecord *) createTrackExtractionRecordForTrack:(TrackDescriptor *)track 
														fileURL:(NSURL *)fileURL
															MD5:(NSString *)MD5
														   SHA1:(NSString *)SHA1
												blockErrorFlags:(NSIndexSet *)blockErrorFlags
											accurateRipChecksum:(NSUInteger)accurateRipChecksum
									 accurateRipConfidenceLevel:(NSNumber *)accurateRipConfidenceLevel
						   accurateRipAlternatePressingChecksum:(NSUInteger)accurateRipAlternatePressingChecksum
							 accurateRipAlternatePressingOffset:(NSNumber *)accurateRipAlternatePressingOffset
{
	NSParameterAssert(nil != track);
	NSParameterAssert(nil != fileURL);
	NSParameterAssert(nil != MD5);
	NSParameterAssert(nil != SHA1);
	
	// Create the extraction record
	TrackExtractionRecord *extractionRecord = [NSEntityDescription insertNewObjectForEntityForName:@"TrackExtractionRecord" 
																			inManagedObjectContext:self.managedObjectContext];
	
	extractionRecord.date = [NSDate date];
	extractionRecord.drive = self.driveInformation;
	extractionRecord.inputURL = fileURL;
	extractionRecord.MD5 = MD5;
	extractionRecord.SHA1 = SHA1;
	extractionRecord.track = track;
	
	if(blockErrorFlags)
		extractionRecord.blockErrorFlags = blockErrorFlags;
	
	if(accurateRipChecksum)
		extractionRecord.accurateRipChecksum = [NSNumber numberWithUnsignedInteger:accurateRipChecksum];
	if(accurateRipConfidenceLevel)
		extractionRecord.accurateRipConfidenceLevel = accurateRipConfidenceLevel;
	
	if(accurateRipAlternatePressingChecksum)
		extractionRecord.accurateRipAlternatePressingChecksum = [NSNumber numberWithUnsignedInteger:accurateRipAlternatePressingChecksum];
	if(accurateRipAlternatePressingOffset)
		extractionRecord.accurateRipAlternatePressingOffset = accurateRipAlternatePressingOffset;
	
	return extractionRecord;
}

- (ImageExtractionRecord *) createImageExtractionRecord
{
	[_statusTextField setStringValue:NSLocalizedString(@"Creating image file", @"")];
	[_detailedStatusTextField setStringValue:@""];
	
	// Create the output file
	NSError *error = nil;
	ExtractedAudioFile *imageFile = [ExtractedAudioFile createFileAtURL:temporaryURLWithExtension(@"wav") error:&error];
	if(nil == imageFile)
		return nil;
	
	// Sort the extracted tracks
	NSSortDescriptor *trackNumberSortDescriptor = [[NSSortDescriptor alloc] initWithKey:@"track.number" ascending:YES];
	NSArray *sortedTrackExtractionRecords = [[_trackExtractionRecords allObjects] sortedArrayUsingDescriptors:[NSArray arrayWithObject:trackNumberSortDescriptor]];
	
	NSUInteger imageSectorNumber = 0;
	int8_t buffer [kCDSectorSizeCDDA];
	
	// Loop over all the extracted tracks and concatenate them together
	for(TrackExtractionRecord *trackExtractionRecord in sortedTrackExtractionRecords) {
		// Open the track for reading
		ExtractedAudioFile *trackFile = [ExtractedAudioFile openFileForReadingAtURL:trackExtractionRecord.inputURL error:&error];
		if(nil == trackFile) {
			[imageFile closeFile], imageFile = nil;
			return nil;
		}
		
		NSUInteger fileSectorCount = trackFile.sectorsInFile;
		NSUInteger fileSectorNumber = 0;
		
		while(fileSectorNumber < fileSectorCount) {
			// Read a single sector of data
			NSUInteger sectorsRead = [trackFile readAudioForSectors:NSMakeRange(fileSectorNumber, 1) buffer:buffer error:&error];
			
			if(0 == sectorsRead) {
				[trackFile closeFile], trackFile = nil;
				[imageFile closeFile], imageFile = nil;
				return nil;
			}
			
			// Write it to the output file
			NSUInteger sectorsWritten = [imageFile setAudio:buffer forSectors:NSMakeRange(imageSectorNumber, 1) error:&error];
			
			if(0 == sectorsWritten) {
				[trackFile closeFile], trackFile = nil;
				[imageFile closeFile], imageFile = nil;
				return nil;
			}
			
			++fileSectorNumber;
			++imageSectorNumber;
		}
		
		[trackFile closeFile], trackFile = nil;
	}
	
	// Create the extraction record
	ImageExtractionRecord *extractionRecord = [NSEntityDescription insertNewObjectForEntityForName:@"ImageExtractionRecord" 
																			inManagedObjectContext:self.managedObjectContext];
	
	extractionRecord.date = [NSDate date];
	extractionRecord.disc = self.compactDisc;
	extractionRecord.drive = self.driveInformation;
	extractionRecord.inputURL = imageFile.URL;
	extractionRecord.MD5 = imageFile.MD5;
	extractionRecord.SHA1 = imageFile.SHA1;
	
	[extractionRecord addTracks:_trackExtractionRecords];
	
	[imageFile closeFile], imageFile = nil;
	
	return extractionRecord;
}

@end


@implementation ExtractionViewController (EncodingPreparation)

- (BOOL) prepareTrackForEncoding:(TrackDescriptor *)track
			 extractionOperation:(ExtractionOperation *)operation
			 accurateRipChecksum:(NSUInteger)accurateRipChecksum
	  accurateRipConfidenceLevel:(NSNumber *)accurateRipConfidenceLevel
						   error:(NSError **)error
{
	return [self prepareTrackForEncoding:track
					 extractionOperation:operation
					 accurateRipChecksum:accurateRipChecksum
			  accurateRipConfidenceLevel:accurateRipConfidenceLevel
	accurateRipAlternatePressingChecksum:0
	  accurateRipAlternatePressingOffset:nil
								   error:error];
}

- (BOOL) prepareTrackForEncoding:(TrackDescriptor *)track
			 extractionOperation:(ExtractionOperation *)operation
			 accurateRipChecksum:(NSUInteger)accurateRipChecksum
	  accurateRipConfidenceLevel:(NSNumber *)accurateRipConfidenceLevel
accurateRipAlternatePressingChecksum:(NSUInteger)accurateRipAlternatePressingChecksum
accurateRipAlternatePressingOffset:(NSNumber *)accurateRipAlternatePressingOffset
						   error:(NSError **)error
{
	NSParameterAssert(nil != track);
	NSParameterAssert(nil != operation);
	
	TrackExtractionRecord *extractionRecord = [self createTrackExtractionRecordForTrack:track
																	extractionOperation:operation
																	accurateRipChecksum:accurateRipChecksum
															 accurateRipConfidenceLevel:accurateRipConfidenceLevel
												   accurateRipAlternatePressingChecksum:accurateRipAlternatePressingChecksum
													 accurateRipAlternatePressingOffset:accurateRipAlternatePressingOffset
																				  error:error];
	
	if(!extractionRecord)
		return NO;

	[self addTrackExtractionRecord:extractionRecord];
	
	return YES;
}

- (BOOL) prepareTrackForEncoding:(TrackDescriptor *)track
						 fileURL:(NSURL *)fileURL
							 MD5:(NSString *)MD5
							SHA1:(NSString *)SHA1
			 accurateRipChecksum:(NSUInteger)accurateRipChecksum
	  accurateRipConfidenceLevel:(NSNumber *)accurateRipConfidenceLevel
{
	return [self prepareTrackForEncoding:track
								 fileURL:fileURL
									 MD5:MD5
									SHA1:SHA1
					 accurateRipChecksum:accurateRipChecksum
			  accurateRipConfidenceLevel:accurateRipConfidenceLevel
	accurateRipAlternatePressingChecksum:0
	  accurateRipAlternatePressingOffset:nil];
}

- (BOOL) prepareTrackForEncoding:(TrackDescriptor *)track
						 fileURL:(NSURL *)fileURL
							 MD5:(NSString *)MD5
							SHA1:(NSString *)SHA1
			 accurateRipChecksum:(NSUInteger)accurateRipChecksum
	  accurateRipConfidenceLevel:(NSNumber *)accurateRipConfidenceLevel
accurateRipAlternatePressingChecksum:(NSUInteger)accurateRipAlternatePressingChecksum
accurateRipAlternatePressingOffset:(NSNumber *)accurateRipAlternatePressingOffset
{
	NSParameterAssert(nil != track);
	NSParameterAssert(nil != fileURL);
	NSParameterAssert(nil != MD5);
	NSParameterAssert(nil != SHA1);
	
	TrackExtractionRecord *extractionRecord = [self createTrackExtractionRecordForTrack:track 
																				fileURL:fileURL
																					MD5:MD5
																				   SHA1:SHA1
																	accurateRipChecksum:accurateRipChecksum
															 accurateRipConfidenceLevel:accurateRipConfidenceLevel
												   accurateRipAlternatePressingChecksum:accurateRipAlternatePressingChecksum
													 accurateRipAlternatePressingOffset:accurateRipAlternatePressingOffset];
	
	if(!extractionRecord)
		return NO;
	
	[self addTrackExtractionRecord:extractionRecord];
	
	return YES;
}

- (void) addTrackExtractionRecord:(TrackExtractionRecord *)extractionRecord
{
	NSParameterAssert(nil != extractionRecord);
	
	// Calculate the track's replay gain
	if(addReplayGainDataForTrack(&_rg, extractionRecord.inputURL)) {
		extractionRecord.track.metadata.replayGain = [NSNumber numberWithFloat:replaygain_analysis_get_title_gain(&_rg)];
		extractionRecord.track.metadata.peak = [NSNumber numberWithFloat:replaygain_analysis_get_title_peak(&_rg)];
	}
	else
		[[Logger sharedLogger] logMessageWithLevel:eLogMessageLevelDebug format:@"Unable to calculate replay gain"];
	
	[_trackExtractionRecords addObject:extractionRecord];
	[_tracksTable reloadData];
}

@end


@implementation ExtractionViewController (AccurateRip)

- (NSUInteger) calculateAccurateRipChecksumForTrack:(TrackDescriptor *)track extractionOperation:(ExtractionOperation *)operation
{
	return [self calculateAccurateRipChecksumForTrack:track extractionOperation:operation readOffsetAdjustment:0];
}

- (NSUInteger) calculateAccurateRipChecksumForTrack:(TrackDescriptor *)track extractionOperation:(ExtractionOperation *)operation readOffsetAdjustment:(NSUInteger)readOffsetAdjustment
{
	NSParameterAssert(nil != track);
	NSParameterAssert(nil != operation);
	
	[_detailedStatusTextField setStringValue:NSLocalizedString(@"Calculating AccurateRip checksum", @"")];
	
	return calculateAccurateRipChecksumForFileRegionUsingOffset(operation.URL, 
																NSMakeRange(operation.cushionSectors, operation.sectors.length),
																[self.compactDisc.firstSession.firstTrack.number isEqualToNumber:track.number],
																[self.compactDisc.firstSession.lastTrack.number isEqualToNumber:track.number],
																readOffsetAdjustment);
}


- (NSArray *) determinePossibleAccurateRipOffsetForTrack:(TrackDescriptor *)track URL:(NSURL *)URL
{
	return [self determinePossibleAccurateRipOffsetForTrack:track URL:URL startingSector:0];
}

- (NSArray *) determinePossibleAccurateRipOffsetForTrack:(TrackDescriptor *)track URL:(NSURL *)URL startingSector:(NSUInteger)startingSector;
{
	NSParameterAssert(nil != track);
	NSParameterAssert(nil != URL);
	
	// Scan the extracted file and determine possible AccurateRip offsets
	ReadOffsetCalculationOperation *operation = [[ReadOffsetCalculationOperation alloc ] init];
	
	operation.URL = URL;
	operation.trackID = [track objectID];
	operation.sixSecondPointSector = (6 * CDDA_SECTORS_PER_SECOND) + startingSector;
	operation.maximumOffsetToCheck = (MAXIMUM_OFFSET_TO_CHECK_IN_SECTORS * AUDIO_FRAMES_PER_CDDA_SECTOR);
	
	// Wait for the operation to be ready
	while(![operation isReady])
		[NSThread sleepForTimeInterval:0.25];
	
	// Run the operation in standalone mode
	[_detailedStatusTextField setStringValue:NSLocalizedString(@"Calculating AccurateRip offsets", @"")];
	[operation start];
	
	if(operation.error) {
		[[Logger sharedLogger] logMessageWithLevel:eLogMessageLevelDebug format:@"Error calculating possible AccurateRip offsets: %@", operation.error];
		return nil;
	}
	
	return operation.possibleReadOffsets;
}

@end


@implementation ExtractionViewController (Private)

- (void) removeTemporaryFiles
{
	NSError *error = nil;
	
	// Remove temporary files
	NSArray *temporaryURLS = [_partialExtractions valueForKey:@"URL"];
	for(NSURL *URL in temporaryURLS) {
		if(![[NSFileManager defaultManager] removeItemAtPath:[URL path] error:&error])
			[[Logger sharedLogger] logMessage:@"Error removing temporary file: %@", [error localizedDescription]];
	}

	temporaryURLS = [_wholeExtractions valueForKey:@"URL"];
	for(NSURL *URL in temporaryURLS) {
		if(![[NSFileManager defaultManager] removeItemAtPath:[URL path] error:&error])
			[[Logger sharedLogger] logMessage:@"Error removing temporary file: %@", [error localizedDescription]];
	}

	for(NSURL *URL in _synthesizedTrackURLs) {
		if(![[NSFileManager defaultManager] removeItemAtPath:[URL path] error:&error])
			[[Logger sharedLogger] logMessage:@"Error removing temporary file: %@", [error localizedDescription]];
	}	
}

- (void) resetExtractionState
{
	_synthesizedTrack = nil;
	_wholeExtractions = [NSMutableArray array];
	_partialExtractions = [NSMutableArray array];
	_sectorsNeedingVerification = [NSMutableIndexSet indexSet];
	_synthesizedTrackURLs = [NSMutableArray array];
	_synthesizedTrackSHAs = [NSMutableDictionary dictionary];
}

- (void) startExtractingNextTrack
{
	_currentTrack = nil;
	
	NSArray *tracks = self.orderedTracksRemaining;
	
	if(![tracks count])
		return;
	
	TrackDescriptor *track = [tracks objectAtIndex:0];
	[_trackIDsRemaining removeObject:[track objectID]];
	
	_currentTrack = track;

	[self removeTemporaryFiles];
	[self resetExtractionState];
	
	self.retryCount = 0;
	
	[[Logger sharedLogger] logMessageWithLevel:eLogMessageLevelDebug format:@"Beginning extraction for track %@", track.number];
	
	// Ensure the track's ISRC and pregap have been read
	if(!track.metadata.ISRC) {
		ISRCDetectionOperation *operation = [[ISRCDetectionOperation alloc] init];
		
		operation.disk = self.disk;
		operation.trackID = track.objectID;
		
		[operation addObserver:self forKeyPath:@"isExecuting" options:NSKeyValueObservingOptionNew context:kISRCDetectionKVOContext];
		[operation addObserver:self forKeyPath:@"isCancelled" options:NSKeyValueObservingOptionNew context:kISRCDetectionKVOContext];
		[operation addObserver:self forKeyPath:@"isFinished" options:NSKeyValueObservingOptionNew context:kISRCDetectionKVOContext];
		
		[self.operationQueue addOperation:operation];
	}	
	
	if(!track.pregap) {
		PregapDetectionOperation *operation = [[PregapDetectionOperation alloc] init];
		
		operation.disk = self.disk;
		operation.trackID = track.objectID;
		
		[operation addObserver:self forKeyPath:@"isExecuting" options:NSKeyValueObservingOptionNew context:kPregapDetectionKVOContext];
		[operation addObserver:self forKeyPath:@"isCancelled" options:NSKeyValueObservingOptionNew context:kPregapDetectionKVOContext];
		[operation addObserver:self forKeyPath:@"isFinished" options:NSKeyValueObservingOptionNew context:kPregapDetectionKVOContext];
		
		[self.operationQueue addOperation:operation];
	}	
	
	[self extractWholeTrack:track];
}

- (void) processExtractionOperation:(ExtractionOperation *)operation
{
	NSParameterAssert(nil != operation);
	
	[_progressIndicator setIndeterminate:YES];
	[_progressIndicator startAnimation:self];

	[_detailedStatusTextField setStringValue:NSLocalizedString(@"Analyzing audio", @"")];
	
	// Delete the output file if the operation was cancelled or did not succeed
	if(operation.error || operation.isCancelled) {
		if(operation.error)
			[self presentError:operation.error modalForWindow:[[self view] window] delegate:self didPresentSelector:@selector(didPresentErrorWithRecovery:contextInfo:) contextInfo:NULL];
		
		NSError *error = nil;
		NSFileManager *fileManager = [NSFileManager defaultManager];
		if([fileManager fileExistsAtPath:operation.URL.path] && ![fileManager removeItemAtPath:operation.URL.path error:&error])
			[self presentError:error modalForWindow:[[self view] window] delegate:self didPresentSelector:@selector(didPresentErrorWithRecovery:contextInfo:) contextInfo:NULL];
		
		return;
	}
	
	// Log some information about the operation that just completed
	if(operation.useC2) {
		[[Logger sharedLogger] logMessageWithLevel:eLogMessageLevelDebug format:@"Extracted sectors %u - %u to %@, %u C2 block errors.  MD5 = %@", operation.sectorsRead.firstSector, operation.sectorsRead.lastSector, [operation.URL.path lastPathComponent], operation.blockErrorFlags.count, operation.MD5];
		if([operation.blockErrorFlags count])
			[[Logger sharedLogger] logMessageWithLevel:eLogMessageLevelDebug format:@"C2 block errors for sectors %@", operation.blockErrorFlags];
	}
	else
		[[Logger sharedLogger] logMessageWithLevel:eLogMessageLevelDebug format:@"Extracted sectors %u - %u to %@.  MD5 = %@", operation.sectorsRead.firstSector, operation.sectorsRead.lastSector, [operation.URL.path lastPathComponent], operation.MD5];
	
	// Fetch the track this operation represents
	NSManagedObject *managedObject = [self.managedObjectContext objectWithID:operation.trackID];
	if(![managedObject isKindOfClass:[TrackDescriptor class]])
		return;
	
	TrackDescriptor *track = (TrackDescriptor *)managedObject;			
	
	// Determine if this operation represents a whole track extraction or a partial track extraction
	// and process it accordingly
	if([operation.sectors containsSectorRange:track.sectorRange])
		[self processExtractionOperation:operation forWholeTrack:track];
	else
		[self processExtractionOperation:operation forPartialTrack:track];
	
	// If no tracks are being processed and none remain to be extracted, we are finished			
	if(!_currentTrack && ![_trackIDsRemaining count]) {
		
		[[Logger sharedLogger] logMessageWithLevel:eLogMessageLevelDebug format:@"Extraction finished"];
		
		// Calculate the album replay gain if any tracks were successfully extracted
		if([_trackExtractionRecords count]) {
			track.session.disc.metadata.replayGain = [NSNumber numberWithFloat:replaygain_analysis_get_album_gain(&_rg)];
			track.session.disc.metadata.peak = [NSNumber numberWithFloat:replaygain_analysis_get_album_peak(&_rg)];
		}
		
		// Save changes to the MOC, so others can synchronize
		if([self.managedObjectContext hasChanges]) {
			NSError *error;
			if(![self.managedObjectContext save:&error])
				[self presentError:error modalForWindow:[[self view] window] delegate:self didPresentSelector:@selector(didPresentErrorWithRecovery:contextInfo:) contextInfo:NULL];
		}
		
		// Send the extracted audio to the encoder
		NSError *error = nil;
		if(eExtractionModeIndividualTracks == self.extractionMode) {
			for(TrackExtractionRecord *extractionRecord in _trackExtractionRecords) {
				// If this track can't be encoded, just skip it
				if(![[EncoderManager sharedEncoderManager] encodeTrackExtractionRecord:extractionRecord error:&error]) {
					// Don't leave the input file dangling
					/*success =*/[[NSFileManager defaultManager] removeItemAtPath:[extractionRecord.inputURL path] error:&error];
					[self.managedObjectContext deleteObject:extractionRecord];
					continue;
				}
			}
		}
		else if(eExtractionModeImage == self.extractionMode) {
			// If any tracks failed to extract the image can't be generated
			if([_failedTrackIDs count]) {
				// Remove the track extraction records from the store
				for(TrackExtractionRecord *extractionRecord in _trackExtractionRecords)
					[self.managedObjectContext deleteObject:extractionRecord];
				
				[_trackExtractionRecords removeAllObjects];
			}
			else {
				ImageExtractionRecord *imageExtractionRecord = [self createImageExtractionRecord];
				if(!imageExtractionRecord)
					[self presentError:error
						modalForWindow:[[self view] window]
							  delegate:self
					didPresentSelector:@selector(didPresentErrorWithRecovery:contextInfo:)
						   contextInfo:NULL];
				
				_imageExtractionRecord = imageExtractionRecord;
				
				if(![[EncoderManager sharedEncoderManager] encodeImageExtractionRecord:self.imageExtractionRecord error:&error])
					[self presentError:error 
						modalForWindow:[[self view] window]
							  delegate:self
					didPresentSelector:@selector(didPresentErrorWithRecovery:contextInfo:)
						   contextInfo:NULL];
			}
		}
		else
			[[Logger sharedLogger] logMessage:@"Unknown extraction mode"];
		
		[self.operationQueue cancelAllOperations];
		[self removeTemporaryFiles];
		
		// Remove any active timers
		[_activeTimers makeObjectsPerformSelector:@selector(invalidate)];
		[_activeTimers removeAllObjects];
		
		self.disk = NULL;
		
		[[[[self view] window] windowController] extractionFinishedWithReturnCode:NSOKButton];
	}
}

- (void) processExtractionOperation:(ExtractionOperation *)operation forWholeTrack:(TrackDescriptor *)track
{
	NSParameterAssert(nil != operation);
	NSParameterAssert(nil != track);
	
	// Save this extraction operation
	[_wholeExtractions addObject:operation];
	
	// Calculate the actual AccurateRip checksum of the extracted audio
	NSUInteger trackActualAccurateRipChecksum = [self calculateAccurateRipChecksumForTrack:track extractionOperation:operation];
	
	// Determine the possible AccurateRip offsets for the extracted audio, if any
	NSArray *possibleAccurateRipOffsets = [self determinePossibleAccurateRipOffsetForTrack:track URL:operation.URL startingSector:operation.cushionSectors];
	
	// Determine which pressings (if any) are the primary ones (offset checksum matches with a zero read offset)
	NSPredicate *zeroOffsetPredicate = [NSPredicate predicateWithFormat:@"%K == 0", kReadOffsetKey];
	NSArray *matchingPressingsWithZeroOffset = [possibleAccurateRipOffsets filteredArrayUsingPredicate:zeroOffsetPredicate];
	
	// Regardless of any C2 or other errors, a track is ready for encoding if it matches a track in the AR database
	
#if ENABLE_ACCURATERIP
	// Iterate through each pressing and compare the track's AccurateRip checksums
	if([matchingPressingsWithZeroOffset count]) {
		
		for(NSDictionary *matchingPressingInfo in matchingPressingsWithZeroOffset) {
			NSManagedObjectID *accurateRipTrackID = [matchingPressingInfo objectForKey:kAccurateRipTrackIDKey];
			
			// Fetch the AccurateRipTrackRecord object from the context and ensure it is the correct class
			NSManagedObject *managedObject = [self.managedObjectContext objectWithID:accurateRipTrackID];
			if(![managedObject isKindOfClass:[AccurateRipTrackRecord class]])
				continue;
			
			AccurateRipTrackRecord *accurateRipTrack = (AccurateRipTrackRecord *)managedObject;
			
			// If the track was accurately ripped, prepare it for encoding
			// The encoding will not be performed until all tracks have been extracted
			if([accurateRipTrack.checksum unsignedIntegerValue] == trackActualAccurateRipChecksum) {
				NSError *error = nil;
				
				BOOL trackPrepared = [self prepareTrackForEncoding:track 
											   extractionOperation:operation 
											   accurateRipChecksum:trackActualAccurateRipChecksum 
										accurateRipConfidenceLevel:accurateRipTrack.confidenceLevel
															 error:&error];
				
				if(trackPrepared)
					[self startExtractingNextTrack];
				else
					[self presentError:error
						modalForWindow:[[self view] window]
							  delegate:self
					didPresentSelector:@selector(didPresentErrorWithRecovery:contextInfo:)
						   contextInfo:NULL];
				
				return;
			}
		}
	}
	else if([possibleAccurateRipOffsets count]) {
		[[Logger sharedLogger] logMessageWithLevel:eLogMessageLevelDebug format:@"Using alternate AccurateRip pressing"];
		
		for(NSDictionary *alternatePressingInfo in possibleAccurateRipOffsets) {
			NSManagedObjectID *accurateRipTrackID = [alternatePressingInfo objectForKey:kAccurateRipTrackIDKey];
			
			// Fetch the AccurateRipTrackRecord object from the context and ensure it is the correct class
			NSManagedObject *managedObject = [self.managedObjectContext objectWithID:accurateRipTrackID];
			if(![managedObject isKindOfClass:[AccurateRipTrackRecord class]])
				continue;
			
			AccurateRipTrackRecord *accurateRipTrack = (AccurateRipTrackRecord *)managedObject;
			
			// Calculate the AccurateRip checksum for the alternate pressing
			NSNumber *alternatePressingOffset = [alternatePressingInfo objectForKey:kReadOffsetKey];
			NSUInteger trackAlternateAccurateRipChecksum = [self calculateAccurateRipChecksumForTrack:track
																				  extractionOperation:operation
																				 readOffsetAdjustment:[alternatePressingOffset unsignedIntegerValue]];
			
			// If the track was accurately ripped, prepare it for encoding
			if([accurateRipTrack.checksum unsignedIntegerValue] == trackAlternateAccurateRipChecksum) {
				NSError *error = nil;
				BOOL trackPrepared = [self prepareTrackForEncoding:track 
											   extractionOperation:operation
											   accurateRipChecksum:trackActualAccurateRipChecksum
										accurateRipConfidenceLevel:accurateRipTrack.confidenceLevel
							  accurateRipAlternatePressingChecksum:trackAlternateAccurateRipChecksum 
								accurateRipAlternatePressingOffset:alternatePressingOffset
															 error:&error];

				if(trackPrepared)
					[self startExtractingNextTrack];
				else
					[self presentError:error
						modalForWindow:[[self view] window] 
							  delegate:self 
					didPresentSelector:@selector(didPresentErrorWithRecovery:contextInfo:) 
						   contextInfo:NULL];
				
				return;
			}
		}
	}
#endif
	
	// Re-rip only portions of the track if any C2 block error flags were returned
	if(operation.useC2 && operation.blockErrorFlags.count) {
		NSIndexSet *positionOfErrors = operation.blockErrorFlags;
		
		// Determine which sectors have no C2 errors
		SectorRange *trackSectorRange = track.sectorRange;
		NSMutableIndexSet *sectorsWithNoErrors = [NSMutableIndexSet indexSetWithIndexesInRange:NSMakeRange(trackSectorRange.firstSector, trackSectorRange.length)];
		[sectorsWithNoErrors removeIndexes:positionOfErrors];
		
		// Save the sectors from this operation with no C2 errors
		[self saveSectors:sectorsWithNoErrors fromOperation:operation forTrack:track];
		
		// Mark the bad sectors
		[_sectorsNeedingVerification addIndexes:positionOfErrors];
		
		// And re-extract them
		[self extractSectors:positionOfErrors forTrack:track coalesceRanges:YES];
	}
	// No C2 errors were encountered or C2 is disabled, so use brute-force comparison
	else {
		[_detailedStatusTextField setStringValue:NSLocalizedString(@"Verifying copy integrity", @"")];

		// Check to see if enough matching extractions exist for this track to be encoded
		NSURL *trackURL = [self outputURLForTrack:track];
		
		// If so, prepare the track for encoding
		if(trackURL) {
			[[Logger sharedLogger] logMessageWithLevel:eLogMessageLevelDebug format:@"Number of required track matches reached"];
			
			// Calculate the AR checksum and MD5/SHA1 digests for the track
			NSUInteger accurateRipChecksum = calculateAccurateRipChecksumForFile(trackURL, 
																				 [self.compactDisc.firstSession.firstTrack.number isEqualToNumber:track.number],
																				 [self.compactDisc.firstSession.lastTrack.number isEqualToNumber:track.number]);
			
			NSArray *digests = calculateMD5AndSHA1DigestsForURL(trackURL);
			
			// Prepare the track for encoding
			BOOL trackPrepared = [self prepareTrackForEncoding:track 
													   fileURL:trackURL 
														   MD5:[digests objectAtIndex:0] 
														  SHA1:[digests objectAtIndex:1] 
										   accurateRipChecksum:accurateRipChecksum 
									accurateRipConfidenceLevel:nil];
			
			if(trackPrepared)
				[self startExtractingNextTrack];
		}
		// If not, determine any mismatched sectors and re-extract them
		else {			
			NSIndexSet *mismatchedSectors = [self mismatchedSectorsForTrack:track];
			
			if([mismatchedSectors count]) {
				
				// Construct an index set containing the sectors that matched across all extraction operations
				SectorRange *trackSectorRange = track.sectorRange;
				NSMutableIndexSet *sectorsWithNoErrors = [NSMutableIndexSet indexSetWithIndexesInRange:NSMakeRange(trackSectorRange.firstSector, trackSectorRange.length)];
				[sectorsWithNoErrors removeIndexes:mismatchedSectors];

				// Mark the bad sectors
				[_sectorsNeedingVerification addIndexes:mismatchedSectors];
				
				NSUInteger sectorIndex = [sectorsWithNoErrors firstIndex];
				while(NSNotFound != sectorIndex) {
					
					NSData *sectorData = [self nonInterpolatedDataForSector:sectorIndex];

					// Save the sector data if it matched enough times
					if(sectorData)
						[self saveSector:sectorIndex sectorData:sectorData forTrack:track];
					// Otherwise it needs verification
					else
						[_sectorsNeedingVerification addIndex:sectorIndex];
					
					sectorIndex = [sectorsWithNoErrors indexGreaterThanIndex:sectorIndex];
				}
				
				// Re-extract the bad sectors
				[self extractSectors:_sectorsNeedingVerification forTrack:track coalesceRanges:YES];
			}
			else
				[self extractWholeTrack:track];			
		}
	}
}

- (void) processExtractionOperation:(ExtractionOperation *)operation forPartialTrack:(TrackDescriptor *)track
{
	NSParameterAssert(nil != operation);
	NSParameterAssert(nil != track);
	
	// Which sectors need to be verified?
	if(![_sectorsNeedingVerification count])
		return;
	
	[[Logger sharedLogger] logMessageWithLevel:eLogMessageLevelDebug format:@"Sectors needing verification: %@", _sectorsNeedingVerification];
	
	// Save this extraction operation
	[_partialExtractions addObject:operation];
		
	// Only check sectors that are contained in this extraction operation
	NSIndexSet *operationSectors = [NSIndexSet indexSetWithIndexesInRange:[operation.sectors rangeValue]];
	NSIndexSet *sectorsToCheck = [_sectorsNeedingVerification intersectedIndexSet:operationSectors];
	
	// Check for sectors with existing errors that were resolved by this operation
	NSUInteger sectorIndex = [sectorsToCheck firstIndex];
	while(NSNotFound != sectorIndex) {

		// Check for whole sector matches
		NSData *sectorData = [self nonInterpolatedDataForSector:sectorIndex];

		// If the sector was verified, save it!
		if(sectorData) {
			[[Logger sharedLogger] logMessageWithLevel:eLogMessageLevelDebug format:@"Sector %ld verified", sectorIndex];
			
			[_sectorsNeedingVerification removeIndex:sectorIndex];
			[self saveSector:sectorIndex sectorData:sectorData forTrack:track];
		}
		else {
			// If a whole sector match couldn't be made, attempt to synthesize a sector
			NSData *interpolatedSectorData = [self interpolatedDataForSector:sectorIndex];
			
			// If the sector was successfully interpolated, save it!
			if(interpolatedSectorData) {
				[[Logger sharedLogger] logMessageWithLevel:eLogMessageLevelDebug format:@"Sector %ld verified (interpolated)", sectorIndex];
				
				[_sectorsNeedingVerification removeIndex:sectorIndex];
				[self saveSector:sectorIndex sectorData:interpolatedSectorData forTrack:track];
			}
			
		}
		
		sectorIndex = [sectorsToCheck indexGreaterThanIndex:sectorIndex];
	}
	
	// If all sectors are verified, encode the track if it is verified by AccurateRip or the
	// required number of matches have been reached
	if(![_sectorsNeedingVerification count]) {
		
		[[Logger sharedLogger] logMessageWithLevel:eLogMessageLevelDebug format:@"All sector errors resolved"];
		
		// Cache the results in case the track isn't verified
		[_synthesizedTrackURLs addObject:_synthesizedTrack.URL];
		[_synthesizedTrackSHAs setObject:_synthesizedTrack.SHA1 forKey:_synthesizedTrack.URL];
		
		// Any operations in progress are partial extractions and are no longer needed
		[self.operationQueue cancelAllOperations];
		
		// Finish the file synthesis
		NSURL *fileURL = _synthesizedTrack.URL;
		NSString *MD5 = _synthesizedTrack.MD5;
		NSString *SHA1 = _synthesizedTrack.SHA1;
		
		[_synthesizedTrack closeFile], _synthesizedTrack = nil;
		
		// Calculate the AccurateRip checksum
		NSUInteger accurateRipChecksum = calculateAccurateRipChecksumForFile(fileURL,
																			 [self.compactDisc.firstSession.firstTrack.number isEqualToNumber:track.number],
																			 [self.compactDisc.firstSession.lastTrack.number isEqualToNumber:track.number]);
		
		// Determine the possible AccurateRip offsets for the extracted audio, if any
		NSArray *possibleAccurateRipOffsets = [self determinePossibleAccurateRipOffsetForTrack:track URL:fileURL];
		
		// Determine which pressings (if any) are the primary ones (offset checksum matches with a zero read offset)
		NSPredicate *zeroOffsetPredicate = [NSPredicate predicateWithFormat:@"%K == 0", kReadOffsetKey];
		NSArray *matchingPressingsWithZeroOffset = [possibleAccurateRipOffsets filteredArrayUsingPredicate:zeroOffsetPredicate];
		
#if ENABLE_ACCURATERIP
		// Iterate through each pressing and compare the track's AccurateRip checksums
		if([matchingPressingsWithZeroOffset count]) {
			
			for(NSDictionary *matchingPressingInfo in matchingPressingsWithZeroOffset) {
				NSManagedObjectID *accurateRipTrackID = [matchingPressingInfo objectForKey:kAccurateRipTrackIDKey];
				
				// Fetch the AccurateRipTrackRecord object from the context and ensure it is the correct class
				NSManagedObject *managedObject = [self.managedObjectContext objectWithID:accurateRipTrackID];
				if(![managedObject isKindOfClass:[AccurateRipTrackRecord class]])
					continue;
				
				AccurateRipTrackRecord *accurateRipTrack = (AccurateRipTrackRecord *)managedObject;
				
				[[Logger sharedLogger] logMessageWithLevel:eLogMessageLevelDebug format:@"Track AR checksum = %.8lx, checking against %.8lx", accurateRipChecksum, accurateRipTrack.checksum.unsignedIntegerValue];
				
				// If the track was accurately ripped, ship it off to the encoder
				if([accurateRipTrack.checksum unsignedIntegerValue] == accurateRipChecksum) {					
					BOOL trackPrepared = [self prepareTrackForEncoding:track
															   fileURL:fileURL
																   MD5:MD5
																  SHA1:SHA1
												   accurateRipChecksum:accurateRipChecksum 
											accurateRipConfidenceLevel:accurateRipTrack.confidenceLevel];
					
					if(trackPrepared)
						[self startExtractingNextTrack];
					
					return;
				}
			}
		}
		else if([possibleAccurateRipOffsets count]) {
			[[Logger sharedLogger] logMessage:@"Using alternate AccurateRip pressing"];
			
			for(NSDictionary *alternatePressingInfo in possibleAccurateRipOffsets) {
				NSManagedObjectID *accurateRipTrackID = [alternatePressingInfo objectForKey:kAccurateRipTrackIDKey];
				
				// Fetch the AccurateRipTrackRecord object from the context and ensure it is the correct class
				NSManagedObject *managedObject = [self.managedObjectContext objectWithID:accurateRipTrackID];
				if(![managedObject isKindOfClass:[AccurateRipTrackRecord class]])
					continue;
				
				AccurateRipTrackRecord *accurateRipTrack = (AccurateRipTrackRecord *)managedObject;
				
				// Calculate the AccurateRip checksum for the alternate pressing
				NSNumber *alternatePressingOffset = [alternatePressingInfo objectForKey:kReadOffsetKey];
				NSUInteger trackAlternateAccurateRipChecksum = [self calculateAccurateRipChecksumForTrack:track extractionOperation:operation readOffsetAdjustment:[alternatePressingOffset unsignedIntegerValue]];
				
				[[Logger sharedLogger] logMessageWithLevel:eLogMessageLevelDebug format:@"Track alternate pressing AR checksum = %.8lx, checking against %.8lx", trackAlternateAccurateRipChecksum, accurateRipTrack.checksum.unsignedIntegerValue];
				
				// If the track was accurately ripped, ship it off to the encoder
				if([accurateRipTrack.checksum unsignedIntegerValue] == trackAlternateAccurateRipChecksum) {
					
					BOOL trackPrepared = [self prepareTrackForEncoding:track
															   fileURL:fileURL
																   MD5:MD5
																  SHA1:SHA1
												   accurateRipChecksum:accurateRipChecksum 
											accurateRipConfidenceLevel:accurateRipTrack.confidenceLevel
								  accurateRipAlternatePressingChecksum:trackAlternateAccurateRipChecksum 
									accurateRipAlternatePressingOffset:alternatePressingOffset];
					
					if(trackPrepared)
						[self startExtractingNextTrack];

					return;
				}
			}
		}
#endif
		
		// Check to see if the enough matching extractions exist for this track for it to be encoded
		NSURL *trackURL = [self outputURLForTrack:track];
		
		// If so, prepare the track for encoding
		if(trackURL) {
			[[Logger sharedLogger] logMessageWithLevel:eLogMessageLevelDebug format:@"Number of required track matches reached"];

			// Calculate the AR checksum and MD5/SHA1 digests for the track
			accurateRipChecksum = calculateAccurateRipChecksumForFile(trackURL, 
																	  [self.compactDisc.firstSession.firstTrack.number isEqualToNumber:track.number],
																	  [self.compactDisc.firstSession.lastTrack.number isEqualToNumber:track.number]);
			
			NSArray *digests = calculateMD5AndSHA1DigestsForURL(trackURL);
			
			// Prepare the track for encoding
			BOOL trackPrepared = [self prepareTrackForEncoding:track 
													   fileURL:trackURL 
														   MD5:[digests objectAtIndex:0] 
														  SHA1:[digests objectAtIndex:1] 
										   accurateRipChecksum:accurateRipChecksum 
									accurateRipConfidenceLevel:nil];
			
			if(trackPrepared)
				[self startExtractingNextTrack];
		}
		else {
			[[Logger sharedLogger] logMessageWithLevel:eLogMessageLevelDebug format:@"Required number of track matches not reached, retrying"];
			
			// Retry the track if the maximum retry count hasn't been exceeded
			if(self.retryCount <= self.maxRetries) {
				
				if((_synthesizedTrackURLs.count + _wholeExtractions.count) > self.requiredTrackMatches)
					++_retryCount;
				
				// Remove temporary files for the partial extractions only
				NSError *error = nil;
				for(NSURL *URL in [_partialExtractions valueForKey:@"URL"]) {
					if(![[NSFileManager defaultManager] removeItemAtPath:[URL path] error:&error])
						[[Logger sharedLogger] logMessage:@"Error removing temporary file: %@", [error localizedDescription]];
				}
				
				_partialExtractions = [NSMutableArray array];
				_sectorsNeedingVerification = [NSMutableIndexSet indexSet];
				
				// Get (re)started on the track
				[self extractWholeTrack:track];
			}
			// Failure
			else {
				[[Logger sharedLogger] logMessage:@"Extraction failed for track %@: maximum retry count exceeded", track.number];
				
				[_failedTrackIDs addObject:[track objectID]];
				[_tracksTable reloadData];
				
				// A failure for a single track still allows individual tracks to be extracted
				if(eExtractionModeIndividualTracks == self.extractionMode)
					[self startExtractingNextTrack];
				// If a single tracks fails to extract an image cannot be generated
				else if(eExtractionModeImage == self.extractionMode) {
					// Set the conditions for termination
					_currentTrack = nil;
					[_trackIDsRemaining removeAllObjects];
				}
			}
		}
	}
	else
		[self extractSectors:_sectorsNeedingVerification forTrack:track coalesceRanges:YES];
}

- (NSData *) dataForSector:(NSUInteger)sector interpolate:(BOOL)interpolate
{
	return [self dataForSector:sector interpolate:interpolate useC2:[self.driveInformation.useC2 boolValue]];
}

- (NSData *) dataForSector:(NSUInteger)sector interpolate:(BOOL)interpolate useC2:(BOOL)useC2
{
	return (interpolate ? [self interpolatedDataForSector:sector useC2:useC2] : [self nonInterpolatedDataForSector:sector useC2:useC2]);
}

- (NSData *) nonInterpolatedDataForSector:(NSUInteger)sector
{
	return [self nonInterpolatedDataForSector:sector useC2:[self.driveInformation.useC2 boolValue]];
}

- (NSData *) nonInterpolatedDataForSector:(NSUInteger)sector useC2:(BOOL)useC2
{
	// Iterate over all the whole and partial extraction operations
	NSMutableArray *allOperations = [NSMutableArray arrayWithArray:_wholeExtractions];
	[allOperations addObjectsFromArray:_partialExtractions];

	// Insufficient extractions exist to verify this sector
	if([allOperations count] < self.requiredSectorMatches)
		return nil;
	
	// Iterate through all the extractions and check the sector in question for matches
	NSUInteger operationIndex;
	for(operationIndex = 0; operationIndex < [allOperations count]; ++operationIndex) {
		
		// Compare this extraction operation to all others
		ExtractionOperation *operation = [allOperations objectAtIndex:operationIndex];
		
		// If the operation doesn't contain the sector in question, there is nothing to do
		if(![operation.sectors containsSector:sector])
			continue;
		
		// Use C2 if specified
		if(useC2 && ((operation.useC2 != useC2) || [operation.blockErrorFlags containsIndex:sector]))
			continue;

		// Open the file for reading
		NSError *error = nil;
		ExtractedAudioFile *operationFile = [ExtractedAudioFile openFileForReadingAtURL:operation.URL error:&error];
		if(!operationFile)
			continue;

		// Extract the sector's data
		NSUInteger sectorIndex = [operation.sectors indexForSector:sector];
		NSData *sectorData = [operationFile audioDataForSector:sectorIndex error:&error];
		
		[operationFile closeFile], operationFile = nil;
				
		// Set up match tracking
		NSUInteger matchCount = 0;		
		
		// Iterate through each operation and make the comparisons
		for(ExtractionOperation *otherOperation in allOperations) {
			
			// Don't compare to ourselves
			if(otherOperation == operation)
				continue;
			
			// Skip this operation if it doesn't contain the sector
			if(![otherOperation.sectors containsSector:sector])
				continue;
			
			// Use C2 if specified
			if(useC2 && ((otherOperation.useC2 != useC2) || [otherOperation.blockErrorFlags containsIndex:sector]))
				continue;
			
			// Open the file for reading
			ExtractedAudioFile *otherOperationFile = [ExtractedAudioFile openFileForReadingAtURL:otherOperation.URL error:&error];
			if(!otherOperationFile)
				continue;
			
			// Extract the sector's data
			NSUInteger otherSectorIndex = [otherOperation.sectors indexForSector:sector];
			NSData *otherSectorData = [otherOperationFile audioDataForSector:otherSectorIndex error:&error];
			
			[otherOperationFile closeFile], otherOperationFile = nil;

			// Compare the sectors
			if([sectorData isEqualToData:otherSectorData])
				++matchCount;
		}
		
		if(matchCount >= self.requiredSectorMatches)
			return sectorData;
	}
	
	return nil;
}

- (NSData *) interpolatedDataForSector:(NSUInteger)sector
{
	return [self interpolatedDataForSector:sector useC2:[self.driveInformation.useC2 boolValue]];
}

- (NSData *) interpolatedDataForSector:(NSUInteger)sector useC2:(BOOL)useC2
{
	// This will (hopefully) contain an error-free version of the sector
	int8_t synthesizedSector [kCDSectorSizeCDDA];

	NSMutableIndexSet *verifiedSectorPositions = [NSMutableIndexSet indexSet];
	
	// Iterate over all the whole and partial extraction operations
	NSMutableArray *allOperations = [NSMutableArray arrayWithArray:_wholeExtractions];
	[allOperations addObjectsFromArray:_partialExtractions];

	// Insufficient extractions exist to verify this sector
	if([allOperations count] < self.requiredSectorMatches)
		return nil;
	
	// Iterate through all the extractions and check the sector in each one for matching bytes
	NSUInteger operationIndex;
	for(operationIndex = 0; operationIndex < [allOperations count]; ++operationIndex) {

		// Compare this extraction operation to all others
		ExtractionOperation *operation = [allOperations objectAtIndex:operationIndex];
		
		// If the operation doesn't contain the sector in question, there is nothing to do
		if(![operation.sectors containsSector:sector])
			continue;

		// Use C2 if specified
		if(useC2 && (operation.useC2 != useC2))
			continue;
		
		// Open the file for reading
		NSError *error = nil;
		ExtractedAudioFile *operationFile = [ExtractedAudioFile openFileForReadingAtURL:operation.URL error:&error];
		if(!operationFile)
			continue;
		
		// Extract the sector's data
		NSUInteger sectorIndex = [operation.sectors indexForSector:sector];
		NSData *sectorData = [operationFile audioDataForSector:sectorIndex error:&error];
		const int8_t *rawSectorBytes = [sectorData bytes];
		
		[operationFile closeFile], operationFile = nil;

		// Determine which bytes in the sector are valid (free of C2 errors)
		NSData *sectorErrorData = [operation.errorFlags objectForKey:[NSNumber numberWithUnsignedInteger:sectorIndex]];
		
		NSIndexSet *errorFreePositions = nil;

		// If sectorErrorData is nil it means no C2 errors exist for the sector
		if(sectorErrorData) {
			BitArray *sectorErrors = [[BitArray alloc] initWithData:sectorErrorData];
			errorFreePositions = [sectorErrors indexSetForZeroes];
		}
		
		// Set up match tracking
		NSUInteger matchCounts [kCDSectorSizeCDDA];		
		memset(&matchCounts, 0, kCDSectorSizeCDDA * sizeof(NSUInteger));
				
		// Iterate through each operation and make the comparisons
		for(ExtractionOperation *otherOperation in allOperations) {
			
			// Don't compare to ourselves
			if(otherOperation == operation)
				continue;
			
			// Skip this operation if it doesn't contain the sector
			if(![otherOperation.sectors containsSector:sector])
				continue;

			// Use C2 if specified
			if(useC2 && (otherOperation.useC2 != useC2))
				continue;
			
			// Open the file for reading
			ExtractedAudioFile *otherOperationFile = [ExtractedAudioFile openFileForReadingAtURL:otherOperation.URL error:&error];
			if(!otherOperationFile)
				continue;
						
			// Extract the sector's data
			NSUInteger otherSectorIndex = [otherOperation.sectors indexForSector:sector];
			NSData *otherSectorData = [otherOperationFile audioDataForSector:otherSectorIndex error:&error];
			const int8_t *otherRawSectorBytes = [otherSectorData bytes];
			
			[otherOperationFile closeFile], otherOperationFile = nil;
			
			// Determine which bytes in the sector are valid (free of C2 errors)
			NSData *otherSectorErrorData = [otherOperation.errorFlags objectForKey:[NSNumber numberWithUnsignedInteger:otherSectorIndex]];
			
			NSIndexSet *otherErrorFreePositions = nil;

			// If otherSectorErrorData is nil it means no C2 errors exist for the sector
			if(otherSectorErrorData) {
				BitArray *otherSectorErrors = [[BitArray alloc] initWithData:otherSectorErrorData];
				otherErrorFreePositions = [otherSectorErrors indexSetForZeroes];
			}
			
			// Determine which positions to compare
			NSIndexSet *semiVerifiedPositions = nil;

			// If C2 is disabled, disregard the error flags, otherwise determine which positions may be valid
			if(useC2) {
				if(errorFreePositions && otherErrorFreePositions)
					semiVerifiedPositions = [errorFreePositions intersectedIndexSet:otherErrorFreePositions];
				else if(errorFreePositions)
					semiVerifiedPositions = errorFreePositions;
				else if(otherErrorFreePositions)
					semiVerifiedPositions = otherErrorFreePositions;
				// No error flags, so all positions may be good
				else
					semiVerifiedPositions = [NSIndexSet indexSetWithIndexesInRange:NSMakeRange(0, kCDSectorSizeCDDA)];
			}
			else
				semiVerifiedPositions = [NSIndexSet indexSetWithIndexesInRange:NSMakeRange(0, kCDSectorSizeCDDA)];
	
			// If the error-free areas don't overlap, there is nothing left to check
			if(0 == [semiVerifiedPositions count])
				continue;
			
			NSUInteger currentPosition = [semiVerifiedPositions firstIndex];
			while(NSNotFound != currentPosition) {
				
				// A match!
				if(*(rawSectorBytes + currentPosition) == *(otherRawSectorBytes + currentPosition))
					matchCounts[currentPosition]++;
				
				currentPosition = [semiVerifiedPositions indexGreaterThanIndex:currentPosition];
			}
		}
		
		// If the required number of matches were made, save those sector positions
		NSUInteger sectorPosition;
		for(sectorPosition = 0; sectorPosition < kCDSectorSizeCDDA; ++sectorPosition) {
			if(matchCounts[sectorPosition] >= self.requiredSectorMatches) {
				synthesizedSector[sectorPosition] = rawSectorBytes[sectorPosition];
				
				[verifiedSectorPositions addIndex:sectorPosition];
			}
		}
	}
	
	// If all kCDSectorSizeCDDA bytes were matched, we've succeeded!
	if(kCDSectorSizeCDDA == [verifiedSectorPositions count])
		return [NSData dataWithBytes:synthesizedSector length:kCDSectorSizeCDDA];		
	else
		return nil;
}

- (NSIndexSet *) mismatchedSectorsForTrack:(TrackDescriptor *)track
{
	return [self mismatchedSectorsForTrack:track useC2:[self.driveInformation.useC2 boolValue]];
}

- (NSIndexSet *) mismatchedSectorsForTrack:(TrackDescriptor *)track useC2:(BOOL)useC2
{
	NSParameterAssert(nil != track);
	
	NSMutableArray *allMismatchedSectors = [NSMutableArray array];
	
	// First iterate through all the whole extractions and compare to the other whole extractions
	// and synthesized tracks
	NSUInteger trackIndex;
	for(trackIndex = 0; trackIndex < [_wholeExtractions count]; ++trackIndex) {
		
		ExtractionOperation *operation = [_wholeExtractions objectAtIndex:trackIndex];
		
		// Use C2 if specified
		if(useC2 && (operation.useC2 != useC2))
			continue;
		
		// Compare to the whole extraction operations
		for(ExtractionOperation *otherOperation in _wholeExtractions) {
			
			// Skip ourselves
			if(operation == otherOperation)
				continue;
			
			// Use C2 if specified
			if(useC2 && (otherOperation.useC2 != useC2))
				continue;
			
			// Determine which sectors don't match
			NSIndexSet *nonMatchingSectorIndexes = compareFileRegionsForNonMatchingSectors(operation.URL, operation.cushionSectors,
																						   otherOperation.URL, otherOperation.cushionSectors,
																						   operation.sectors.length);
			
			// Convert from sector indexes to sector numbers				
			NSMutableIndexSet *nonMatchingSectors = [nonMatchingSectorIndexes mutableCopy];
			[nonMatchingSectors shiftIndexesStartingAtIndex:[nonMatchingSectorIndexes firstIndex] by:operation.sectors.firstSector];
			[allMismatchedSectors addObject:nonMatchingSectors];
		}
		
		// Compare to the synthesized tracks
		for(NSURL *synthesizedTrackURL in _synthesizedTrackURLs) {
			
			NSIndexSet *nonMatchingSectorIndexes = compareFileRegionsForNonMatchingSectors(operation.URL, operation.cushionSectors,
																						   synthesizedTrackURL, 0,
																						   operation.sectors.length);
			
			// Convert from sector indexes to sector numbers				
			NSMutableIndexSet *nonMatchingSectors = [nonMatchingSectorIndexes mutableCopy];
			[nonMatchingSectors shiftIndexesStartingAtIndex:[nonMatchingSectorIndexes firstIndex] by:operation.sectors.firstSector];
			[allMismatchedSectors addObject:nonMatchingSectors];
		}
	}
	
	// Iterate through each synthesized track
	for(trackIndex = 0; trackIndex < [_synthesizedTrackURLs count]; ++trackIndex) {
		
		NSURL *synthesizedTrackURL = [_synthesizedTrackURLs objectAtIndex:trackIndex];
		
		// Compare to the whole extraction operations
		for(ExtractionOperation *operation in _wholeExtractions) {
			
			// Use C2 if specified
			if(useC2 && (operation.useC2 != useC2))
				continue;
			
			NSIndexSet *nonMatchingSectorIndexes = compareFileRegionsForNonMatchingSectors(synthesizedTrackURL, 0,
																						   operation.URL, operation.cushionSectors,
																						   operation.sectors.length);
						
			// Convert from sector indexes to sector numbers				
			NSMutableIndexSet *nonMatchingSectors = [nonMatchingSectorIndexes mutableCopy];
			[nonMatchingSectors shiftIndexesStartingAtIndex:[nonMatchingSectorIndexes firstIndex] by:track.sectorRange.firstSector];
			[allMismatchedSectors addObject:nonMatchingSectors];
		}
		
		// Compare to the synthesized tracks
		for(NSURL *otherSynthesizedTrackURL in _synthesizedTrackURLs) {
			
			// Skip ourselves
			if(synthesizedTrackURL == otherSynthesizedTrackURL)
				continue;
			
			NSIndexSet *nonMatchingSectorIndexes = compareFilesForNonMatchingSectors(synthesizedTrackURL, otherSynthesizedTrackURL);
			
			// Convert from sector indexes to sector numbers				
			NSMutableIndexSet *nonMatchingSectors = [nonMatchingSectorIndexes mutableCopy];
			[nonMatchingSectors shiftIndexesStartingAtIndex:[nonMatchingSectorIndexes firstIndex] by:track.sectorRange.firstSector];
			[allMismatchedSectors addObject:nonMatchingSectors];
		}
	}
	
	//NSMutableIndexSet *allTrackSectors = [NSMutableIndexSet indexSetWithIndexesInRange:[track.sectorRange rangeValue]];
	NSMutableIndexSet *foo = [NSMutableIndexSet indexSet];
	
	for(NSIndexSet *mismatchedSectors in allMismatchedSectors) {
		[foo addIndexes:mismatchedSectors];
	}
	
	return [foo copy];
}

- (NSURL *) outputURLForTrack:(TrackDescriptor *)track
{
	return [self outputURLForTrack:track useC2:[self.driveInformation.useC2 boolValue]];
}

- (NSURL *) outputURLForTrack:(TrackDescriptor *)track useC2:(BOOL)useC2
{
	NSParameterAssert(nil != track);
	
	// For a track to be successfully extracted, it must match self.requiredMatches
	// other track extractions as determined by SHA1 comparisons

	// A track can be generated in two ways- via a single extraction operation or 
	// synthesized sector-by-sector, so for completeness it is necessary to compare them all
	
	NSError *error = nil;

	// First iterate through all the whole extractions and compare to the other whole extractions
	// and synthesized tracks
	NSUInteger trackIndex;
	for(trackIndex = 0; trackIndex < [_wholeExtractions count]; ++trackIndex) {
		
		ExtractionOperation *operation = [_wholeExtractions objectAtIndex:trackIndex];		
		NSUInteger matchCount = 0;

		// Use C2 if specified
		if(useC2 && ((operation.useC2 != useC2) || ([operation.blockErrorFlags count])))
			continue;
		
		// Compare to the whole extraction operations
		for(ExtractionOperation *otherOperation in _wholeExtractions) {
			
			// Skip ourselves
			if(operation == otherOperation)
				continue;
			
			// Use C2 if specified
			if(useC2 && ((otherOperation.useC2 != useC2) || ([otherOperation.blockErrorFlags count])))
				continue;			
			
			// If the SHA1 hashes match, we've a match
			if([operation.SHA1 isEqualToString:otherOperation.SHA1])
				++matchCount;
		}
		
		// Compare to the synthesized tracks
		for(NSURL *synthesizedTrackURL in _synthesizedTrackURLs) {

			// If the two tracks match, record it
			NSString *synthesizedSHA1 = [_synthesizedTrackSHAs objectForKey:synthesizedTrackURL];
			
			if([operation.SHA1 isEqualToString:synthesizedSHA1])
				++matchCount;
		}

		// If the required number of matches were made, the track is ready for encoding
		if(matchCount >= self.requiredTrackMatches)
			return [self generateOutputFileForOperation:operation error:&error];
	}
		
	// If a match wasn't yet made, iterate through each synthesized track
	for(trackIndex = 0; trackIndex < [_synthesizedTrackURLs count]; ++trackIndex) {
		
		NSURL *synthesizedTrackURL = [_synthesizedTrackURLs objectAtIndex:trackIndex];
		NSString *synthesizedSHA1 = [_synthesizedTrackSHAs objectForKey:synthesizedTrackURL];
		NSUInteger matchCount = 0;

		// Compare to the whole extraction operations
		for(ExtractionOperation *operation in _wholeExtractions) {
			
			// Use C2 if specified
			if(useC2 && ((operation.useC2 != useC2) || ([operation.blockErrorFlags count])))
				continue;			
			
			// If the SHA1 hashes match, we've a match
			if([synthesizedSHA1 isEqualToString:operation.SHA1])
				++matchCount;
		}
		
		// Compare to the synthesized tracks
		for(NSURL *otherSynthesizedTrackURL in _synthesizedTrackURLs) {
			
			// Skip ourselves
			if(synthesizedTrackURL == otherSynthesizedTrackURL)
				continue;

			NSString *otherSynthesizedSHA1 = [_synthesizedTrackSHAs objectForKey:otherSynthesizedTrackURL];
			
			// If the two tracks match, record it
			if([synthesizedSHA1 isEqualToString:otherSynthesizedSHA1])
				++matchCount;
		}
		
		// If the required number of matches were made, the track is ready for encoding
		if(matchCount >= self.requiredTrackMatches)
			return synthesizedTrackURL;
	}

	// The required number of matches was not reached
	return nil;
}

- (BOOL) saveSector:(NSUInteger)sector sectorData:(NSData *)sectorData forTrack:(TrackDescriptor *)track
{
	NSParameterAssert(nil != sectorData);
	NSParameterAssert(nil != track);
	
	NSError *error = nil;

	// Create the output file if it doesn't exist
	if(!_synthesizedTrack) {
		_synthesizedTrack = [ExtractedAudioFile createFileAtURL:temporaryURLWithExtension(@"wav") error:&error];
		if(!_synthesizedTrack) {
			[self presentError:error modalForWindow:[[self view] window] delegate:self didPresentSelector:@selector(didPresentErrorWithRecovery:contextInfo:) contextInfo:NULL];
			return NO;
		}
	}
	
	[_synthesizedTrack setAudioData:sectorData forSector:[track.sectorRange indexForSector:sector] error:&error];
	
	return YES;
}

- (BOOL) saveSectors:(NSIndexSet *)sectors fromOperation:(ExtractionOperation *)operation forTrack:(TrackDescriptor *)track
{
	NSParameterAssert(nil != sectors);
	NSParameterAssert(nil != operation);
	NSParameterAssert(nil != track);
	
	// Open the source file for reading
	NSError *error = nil;
	ExtractedAudioFile *inputFile = [ExtractedAudioFile openFileForReadingAtURL:operation.URL error:&error];
	if(!inputFile) {
		[self presentError:error modalForWindow:[[self view] window] delegate:self didPresentSelector:@selector(didPresentErrorWithRecovery:contextInfo:) contextInfo:NULL];
		return NO;
	}
	
	// Create the output file if it doesn't exist
	if(!_synthesizedTrack) {
		_synthesizedTrack = [ExtractedAudioFile createFileAtURL:temporaryURLWithExtension(@"wav") error:&error];
		if(!_synthesizedTrack) {
			[inputFile closeFile], inputFile = nil;
			[self presentError:error modalForWindow:[[self view] window] delegate:self didPresentSelector:@selector(didPresentErrorWithRecovery:contextInfo:) contextInfo:NULL];
			return NO;
		}
	}
	
	// Convert the absolute sector numbers to indexes within the extracted audio
	NSUInteger trackFirstSector = track.sectorRange.firstSector;
	NSUInteger firstSectorInInputFile = operation.sectors.firstSector;
	NSUInteger inputFileCushionSectors = operation.cushionSectors;
	
	// Copy and save the specified sectors, combining ranges to minimize reads
	NSUInteger firstIndex = NSNotFound;
	NSUInteger latestIndex = NSNotFound;
	NSUInteger sectorIndex = [sectors firstIndex];
	
	for(;;) {
		// Last sector
		if(NSNotFound == sectorIndex) {
			if(NSNotFound != firstIndex) {
				if(firstIndex == latestIndex) {
					NSData *sectorData = [inputFile audioDataForSector:(firstIndex - firstSectorInInputFile + inputFileCushionSectors) error:&error];
					[_synthesizedTrack setAudioData:sectorData forSector:(firstIndex - trackFirstSector) error:&error];
				}
				else {
					NSUInteger sectorCount = latestIndex - firstIndex + 1;
					NSData *sectorsData = [inputFile audioDataForSectors:NSMakeRange(firstIndex - firstSectorInInputFile + inputFileCushionSectors, sectorCount) error:&error];
					[_synthesizedTrack setAudioData:sectorsData forSectors:NSMakeRange(firstIndex - trackFirstSector, sectorCount) error:&error];
				}
			}
			
			break;
		}
		
		// Consolidate this sector into the current range
		if(latestIndex == (sectorIndex - 1))
			latestIndex = sectorIndex;
		// Store the previous range and start a new one
		else {
			if(NSNotFound != firstIndex) {
				if(firstIndex == latestIndex) {
					NSData *sectorData = [inputFile audioDataForSector:(firstIndex - firstSectorInInputFile + inputFileCushionSectors) error:&error];
					[_synthesizedTrack setAudioData:sectorData forSector:(firstIndex - trackFirstSector) error:&error];
				}
				else {
					NSUInteger sectorCount = latestIndex - firstIndex + 1;
					NSData *sectorsData = [inputFile audioDataForSectors:NSMakeRange(firstIndex - firstSectorInInputFile + inputFileCushionSectors, sectorCount) error:&error];
					[_synthesizedTrack setAudioData:sectorsData forSectors:NSMakeRange(firstIndex - trackFirstSector, sectorCount) error:&error];
				}
			}
			
			firstIndex = sectorIndex;
			latestIndex = sectorIndex;
		}
		
		sectorIndex = [sectors indexGreaterThanIndex:sectorIndex];
	}
	
	[inputFile closeFile], inputFile = nil;
	
	return YES;
}

@end
