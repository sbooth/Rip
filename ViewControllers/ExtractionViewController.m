/*
 *  Copyright (C) 2008 - 2009 Stephen F. Booth <me@sbooth.org>
 *  All Rights Reserved
 */

#import "ExtractionViewController.h"
#import "ExtractionViewController+AudioExtraction.h"
#import "ExtractionViewController+ExtractionRecordCreation.h"

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
NSString * const kMCNDetectionKVOContext		= @"org.sbooth.Rip.ExtractionViewController.MCNDetectionKVOContext";
NSString * const kISRCDetectionKVOContext		= @"org.sbooth.Rip.ExtractionViewController.ISRCDetectionKVOContext";
NSString * const kPregapDetectionKVOContext		= @"org.sbooth.Rip.ExtractionViewController.PregapDetectionKVOContext";
NSString * const kAudioExtractionKVOContext		= @"org.sbooth.Rip.ExtractionViewController.AudioExtractionKVOContext";

// ========================================
// For debugging
// ========================================
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
// The real work is done here
// ========================================
@interface ExtractionViewController (Private)
- (void) removeTemporaryFiles;
- (void) resetExtractionState;

- (void) startExtractingNextTrack;

- (void) processExtractionOperation:(ExtractionOperation *)operation;
- (void) processWholeTrackExtractionOperation:(ExtractionOperation *)operation;
- (void) processPartialTrackExtractionOperation:(ExtractionOperation *)operation;

- (NSData *) dataForSector:(NSUInteger)sector interpolate:(BOOL)interpolate;
- (NSData *) dataForSector:(NSUInteger)sector interpolate:(BOOL)interpolate useC2:(BOOL)useC2;
- (NSData *) dataForSector:(NSUInteger)sector interpolate:(BOOL)interpolate requiredMatches:(NSUInteger)requiredMatches useC2:(BOOL)useC2;

- (NSData *) nonInterpolatedDataForSector:(NSUInteger)sector;
- (NSData *) nonInterpolatedDataForSector:(NSUInteger)sector useC2:(BOOL)useC2;
- (NSData *) nonInterpolatedDataForSector:(NSUInteger)sector requiredMatches:(NSUInteger)requiredMatches useC2:(BOOL)useC2;

- (NSData *) interpolatedDataForSector:(NSUInteger)sector;
- (NSData *) interpolatedDataForSector:(NSUInteger)sector useC2:(BOOL)useC2;
- (NSData *) interpolatedDataForSector:(NSUInteger)sector requiredMatches:(NSUInteger)requiredMatches useC2:(BOOL)useC2;

- (NSIndexSet *) mismatchedSectors;
- (NSIndexSet *) mismatchedSectorsUsingC2:(BOOL)useC2;

- (NSURL *) outputURL;
- (NSURL *) outputURLUsingC2:(BOOL)useC2;

- (NSURL *) bestGuessURL;
- (NSURL *) bestGuessURLUsingC2:(BOOL)useC2;

- (BOOL) verifyTrackWithAccurateRip:(NSURL *)inputURL;

- (BOOL) saveSector:(NSUInteger)sector sectorData:(NSData *)sectorData;
- (BOOL) saveSectors:(NSIndexSet *)sectors fromOperation:(ExtractionOperation *)operation;

- (BOOL) saveTrackFromURL:(NSURL *)trackWithCushionSectorsURL;
- (BOOL) saveTrackFromURL:(NSURL *)trackWithCushionSectorsURL copyVerified:(BOOL)copyVerified;

- (BOOL) saveTrackFromURL:(NSURL *)trackWithCushionSectorsURL accurateRipChecksum:(NSUInteger)accurateRipChecksum accurateRipConfidenceLevel:(NSNumber *)accurateRipConfidenceLevel;
- (BOOL) saveTrackFromURL:(NSURL *)trackWithCushionSectorsURL accurateRipChecksum:(NSUInteger)accurateRipChecksum accurateRipConfidenceLevel:(NSNumber *)accurateRipConfidenceLevel accurateRipAlternatePressingChecksum:(NSUInteger)accurateRipAlternatePressingChecksum accurateRipAlternatePressingOffset:(NSNumber *)accurateRipAlternatePressingOffset;
@end

@implementation ExtractionViewController

@synthesize disk = _disk;
@synthesize trackIDs = _trackIDs;

@synthesize maxRetries = _maxRetries;
@synthesize requiredSectorMatches = _requiredSectorMatches;
@synthesize requiredTrackMatches = _requiredTrackMatches;
@synthesize allowExtractionFailure = _allowExtractionFailure;
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
	else if(kAudioExtractionKVOContext == context) {
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
	
	// Create a user-friendly representation of the track being processed
	if(_currentTrack.metadata.title)
		[_statusTextField setStringValue:_currentTrack.metadata.title];
	else
		[_statusTextField setStringValue:[_currentTrack.number stringValue]];
	
	// Determine if this operation represents a whole track extraction or a partial track extraction
	BOOL isWholeTrack = [operation.sectors isEqualToSectorRange:_sectorsToExtract];
	
	// Check to see if this track has been extracted before
	if(!isWholeTrack)
		[_detailedStatusTextField setStringValue:[NSString stringWithFormat:NSLocalizedString(@"Re-extracting sectors %ld - %ld", @""), operation.sectors.firstSector, operation.sectors.lastSector]];
	else if([_wholeExtractions count])
		[_detailedStatusTextField setStringValue:NSLocalizedString(@"Re-extracting audio", @"")];
	else
		[_detailedStatusTextField setStringValue:NSLocalizedString(@"Extracting audio", @"")];
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
	_retryCount = 0;
	_synthesizedTrackURL = nil;
	_sectorsToExtract = nil;
	_wholeExtractions = [NSMutableArray array];
	_partialExtractions = [NSMutableArray array];
	_sectorsNeedingVerification = [NSMutableIndexSet indexSet];
	_synthesizedTrackURLs = [NSMutableArray array];
	_synthesizedTrackSHAs = [NSMutableDictionary dictionary];
}

- (void) startExtractingNextTrack
{
	// Clean up and reset in preparation for extraction
	_currentTrack = nil;

	[self removeTemporaryFiles];
	[self resetExtractionState];

	// Get the next track to be extracted, if any remain
	NSArray *tracks = self.orderedTracksRemaining;
	
	if(![tracks count])
		return;
	
	TrackDescriptor *track = [tracks objectAtIndex:0];
	[_trackIDsRemaining removeObject:[track objectID]];
	
	_currentTrack = track;
	
	// To allow for Accurate Rip verification of alternate disc pressings, a buffer of MAXIMUM_OFFSET_TO_CHECK_IN_SECTORS
	// will be extracted on either side of the track
	NSInteger firstSectorToRead = track.sectorRange.firstSector - MAXIMUM_OFFSET_TO_CHECK_IN_SECTORS;
	NSInteger lastSectorToRead = track.sectorRange.lastSector + MAXIMUM_OFFSET_TO_CHECK_IN_SECTORS;

	// Limit the sectors to be extracted to those in the first session, so as not to over-read the lead in or lead out
	SectorRange *firstSessionSectors = self.compactDisc.firstSession.sectorRange;	
	NSInteger firstPermissibleSector = firstSessionSectors.firstSector;
	NSInteger lastPermissibleSector = firstSessionSectors.lastSector;
	
	// To calculate the offset AccurateRip checksums, silence may be prepended or appended to the extracted audio
	_sectorsOfSilenceToPrepend = 0;
	if(firstSectorToRead < firstPermissibleSector) {
		_sectorsOfSilenceToPrepend = firstPermissibleSector - firstSectorToRead;
		firstSectorToRead = firstPermissibleSector;
	}
	
	_sectorsOfSilenceToAppend = 0;
	if(lastSectorToRead > lastPermissibleSector) {
		_sectorsOfSilenceToAppend = lastSectorToRead - lastPermissibleSector;
		lastSectorToRead = lastPermissibleSector;
	}

	// This is the range of sectors that will be extracted
	_sectorsToExtract = [SectorRange sectorRangeWithFirstSector:firstSectorToRead lastSector:lastSectorToRead];
	
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
	
	// Get going on the extraction
	[self extractSectorRange:_sectorsToExtract];
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
	
	// Determine if this operation represents a whole track extraction or a partial track extraction
	// and process it accordingly
	if([operation.sectors isEqualToSectorRange:_sectorsToExtract])
		[self processWholeTrackExtractionOperation:operation];
	else
		[self processPartialTrackExtractionOperation:operation];
	
	// If no tracks are being processed and none remain to be extracted, we are finished			
	if(!_currentTrack && ![_trackIDsRemaining count]) {
		
		[[Logger sharedLogger] logMessageWithLevel:eLogMessageLevelDebug format:@"Extraction finished"];
		
		// Calculate the album replay gain if any tracks were successfully extracted
		if([_trackExtractionRecords count]) {
			self.compactDisc.metadata.replayGain = [NSNumber numberWithFloat:replaygain_analysis_get_album_gain(&_rg)];
			self.compactDisc.metadata.peak = [NSNumber numberWithFloat:replaygain_analysis_get_album_peak(&_rg)];
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

- (void) processWholeTrackExtractionOperation:(ExtractionOperation *)operation
{
	NSParameterAssert(nil != operation);
	
	// Save this extraction operation
	[_wholeExtractions addObject:operation];
		
	if(ENABLE_ACCURATERIP && [self verifyTrackWithAccurateRip:operation.URL])
		[self startExtractingNextTrack];
	// Re-rip only portions of the track if any C2 block error flags were returned
	else if(operation.useC2 && operation.blockErrorFlags.count) {
		NSIndexSet *positionOfErrors = operation.blockErrorFlags;
		
		// Determine which sectors have no C2 errors
		NSMutableIndexSet *sectorsWithNoErrors = [NSMutableIndexSet indexSetWithIndexesInRange:[_sectorsToExtract rangeValue]];
		[sectorsWithNoErrors removeIndexes:positionOfErrors];
		
		// Save the sectors from this operation with no C2 errors
		[self saveSectors:sectorsWithNoErrors fromOperation:operation];
		
		// Mark the bad sectors
		[_sectorsNeedingVerification addIndexes:positionOfErrors];
		
		// And re-extract them
		[self extractSectors:positionOfErrors coalesceRanges:YES];
	}
	// No C2 errors were encountered or C2 is disabled, so use brute-force comparison
	else {
		[_detailedStatusTextField setStringValue:NSLocalizedString(@"Verifying copy integrity", @"")];

		// Check to see if enough matching extractions exist for this track to be encoded
		NSURL *trackURL = [self outputURL];
		
		// If so, prepare the track for encoding
		if(trackURL) {
			[[Logger sharedLogger] logMessageWithLevel:eLogMessageLevelDebug format:@"Number of required track matches reached"];

			BOOL trackSaved = [self saveTrackFromURL:trackURL];
			if(trackSaved)
				[self startExtractingNextTrack];
		}
		// If not, determine any mismatched sectors and re-extract them
		else {			
			NSIndexSet *mismatchedSectors = [self mismatchedSectors];
			
			if([mismatchedSectors count]) {
				
				// Construct an index set containing the sectors that matched across all extraction operations
				NSMutableIndexSet *sectorsWithNoErrors = [NSMutableIndexSet indexSetWithIndexesInRange:[_sectorsToExtract rangeValue]];
				[sectorsWithNoErrors removeIndexes:mismatchedSectors];

				// Mark the bad sectors
				[_sectorsNeedingVerification addIndexes:mismatchedSectors];
				
				NSUInteger sectorIndex = [sectorsWithNoErrors firstIndex];
				while(NSNotFound != sectorIndex) {
					
					NSData *sectorData = [self nonInterpolatedDataForSector:sectorIndex];

					// Save the sector data if it matched enough times
					if(sectorData)
						[self saveSector:sectorIndex sectorData:sectorData];
					// Otherwise it needs verification
					else
						[_sectorsNeedingVerification addIndex:sectorIndex];
					
					sectorIndex = [sectorsWithNoErrors indexGreaterThanIndex:sectorIndex];
				}
				
				// Re-extract the bad sectors
				[self extractSectors:_sectorsNeedingVerification coalesceRanges:YES];
			}
			else
				[self extractSectorRange:_sectorsToExtract];
		}
	}
}

- (void) processPartialTrackExtractionOperation:(ExtractionOperation *)operation
{
	NSParameterAssert(nil != operation);
	
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
			[self saveSector:sectorIndex sectorData:sectorData];
		}
		else {
			// If a whole sector match couldn't be made, attempt to synthesize a sector
			NSData *interpolatedSectorData = [self interpolatedDataForSector:sectorIndex];
			
			// If the sector was successfully interpolated, save it!
			if(interpolatedSectorData) {
				[[Logger sharedLogger] logMessageWithLevel:eLogMessageLevelDebug format:@"Sector %ld verified (interpolated)", sectorIndex];
				
				[_sectorsNeedingVerification removeIndex:sectorIndex];
				[self saveSector:sectorIndex sectorData:interpolatedSectorData];
			}
			
		}
		
		sectorIndex = [sectorsToCheck indexGreaterThanIndex:sectorIndex];
	}
	
	// If all sectors are verified, encode the track if it is verified by AccurateRip or the
	// required number of matches have been reached
	if(![_sectorsNeedingVerification count]) {
		
		[[Logger sharedLogger] logMessageWithLevel:eLogMessageLevelDebug format:@"All sector errors resolved"];
		
		// Calculate the SHA1 for the audio
		NSString *SHA1 = calculateSHA1DigestForURL(_synthesizedTrackURL);
		
		// Cache the results in case the track isn't verified
		[_synthesizedTrackURLs addObject:_synthesizedTrackURL];		
		[_synthesizedTrackSHAs setObject:SHA1 forKey:_synthesizedTrackURL];
		
		// Any operations in progress are partial extractions and are no longer needed
		[self.operationQueue cancelAllOperations];
				
		if(ENABLE_ACCURATERIP && [self verifyTrackWithAccurateRip:_synthesizedTrackURL]) {
			[self startExtractingNextTrack];
			return;
		}
		
		NSURL *trackURL = [self outputURL];

		// Check to see if enough matching extractions exist for this track for it to be encoded
		if(trackURL) {
			[[Logger sharedLogger] logMessageWithLevel:eLogMessageLevelDebug format:@"Number of required track matches reached"];

			BOOL trackSaved = [self saveTrackFromURL:trackURL];			
			if(trackSaved)
				[self startExtractingNextTrack];
		}
		else {
			[[Logger sharedLogger] logMessageWithLevel:eLogMessageLevelDebug format:@"Required number of track matches not reached"];
			
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
				[self extractSectorRange:_sectorsToExtract];
			}
			else if(!self.allowExtractionFailure) {
				[[Logger sharedLogger] logMessage:@"Maximum retry count exceeded for track %@, using best guess", _currentTrack.number];
			
				// Since the user doesn't want tracks to fail, just throw the best together we can
				NSURL *bestGuessURL = [self bestGuessURL];
				
				BOOL trackSaved = [self saveTrackFromURL:bestGuessURL copyVerified:NO];
				if(trackSaved)
					[self startExtractingNextTrack];				
			}
			// Failure
			else {
				[[Logger sharedLogger] logMessage:@"Extraction failed for track %@: maximum retry count exceeded", _currentTrack.number];
				
				[_failedTrackIDs addObject:[_currentTrack objectID]];
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
		[self extractSectors:_sectorsNeedingVerification coalesceRanges:YES];
}

- (NSData *) dataForSector:(NSUInteger)sector interpolate:(BOOL)interpolate
{
	return [self dataForSector:sector interpolate:interpolate useC2:[self.driveInformation.useC2 boolValue]];
}

- (NSData *) dataForSector:(NSUInteger)sector interpolate:(BOOL)interpolate useC2:(BOOL)useC2
{
	return [self dataForSector:sector interpolate:interpolate requiredMatches:self.requiredSectorMatches useC2:useC2];
}

- (NSData *) dataForSector:(NSUInteger)sector interpolate:(BOOL)interpolate requiredMatches:(NSUInteger)requiredMatches useC2:(BOOL)useC2
{
	return (interpolate ? [self interpolatedDataForSector:sector requiredMatches:requiredMatches useC2:useC2] : [self nonInterpolatedDataForSector:sector requiredMatches:requiredMatches useC2:useC2]);
}

- (NSData *) nonInterpolatedDataForSector:(NSUInteger)sector
{
	return [self nonInterpolatedDataForSector:sector useC2:[self.driveInformation.useC2 boolValue]];
}

- (NSData *) nonInterpolatedDataForSector:(NSUInteger)sector useC2:(BOOL)useC2
{
	return [self nonInterpolatedDataForSector:sector requiredMatches:self.requiredSectorMatches useC2:useC2];
}

- (NSData *) nonInterpolatedDataForSector:(NSUInteger)sector requiredMatches:(NSUInteger)requiredMatches useC2:(BOOL)useC2
{
	// Iterate over all the whole and partial extraction operations
	NSMutableArray *allOperations = [NSMutableArray arrayWithArray:_wholeExtractions];
	[allOperations addObjectsFromArray:_partialExtractions];

	// Insufficient extractions exist to verify this sector
	if([allOperations count] < requiredMatches)
		return nil;
	
	// Iterate through all the extractions and check the sector in question for matches
	for(NSUInteger operationIndex = 0; operationIndex < [allOperations count]; ++operationIndex) {
		
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
		
		if(matchCount >= requiredMatches)
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
	return [self interpolatedDataForSector:sector requiredMatches:self.requiredSectorMatches useC2:useC2];
}

- (NSData *) interpolatedDataForSector:(NSUInteger)sector requiredMatches:(NSUInteger)requiredMatches useC2:(BOOL)useC2
{
	// This will (hopefully) contain an error-free version of the sector
	int8_t synthesizedSector [kCDSectorSizeCDDA];

	NSMutableIndexSet *verifiedSectorPositions = [NSMutableIndexSet indexSet];
	
	// Iterate over all the whole and partial extraction operations
	NSMutableArray *allOperations = [NSMutableArray arrayWithArray:_wholeExtractions];
	[allOperations addObjectsFromArray:_partialExtractions];

	// Insufficient extractions exist to verify this sector
	if([allOperations count] < requiredMatches)
		return nil;
	
	// Iterate through all the extractions and check the sector in each one for matching bytes
	for(NSUInteger operationIndex = 0; operationIndex < [allOperations count]; ++operationIndex) {

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
		for(NSUInteger sectorPosition = 0; sectorPosition < kCDSectorSizeCDDA; ++sectorPosition) {
			if(matchCounts[sectorPosition] >= requiredMatches) {
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

- (NSIndexSet *) mismatchedSectors
{
	return [self mismatchedSectorsUsingC2:[self.driveInformation.useC2 boolValue]];
}

- (NSIndexSet *) mismatchedSectorsUsingC2:(BOOL)useC2
{
	NSMutableArray *allMismatchedSectors = [NSMutableArray array];
	
	// First iterate through all the whole extractions and compare to the other whole extractions
	// and synthesized tracks
	for(NSUInteger trackIndex = 0; trackIndex < [_wholeExtractions count]; ++trackIndex) {
		
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
			NSIndexSet *nonMatchingSectorIndexes = compareFilesForNonMatchingSectors(operation.URL, otherOperation.URL);
			
			// Convert from sector indexes to sector numbers				
			NSMutableIndexSet *nonMatchingSectors = [nonMatchingSectorIndexes mutableCopy];
			[nonMatchingSectors shiftIndexesStartingAtIndex:[nonMatchingSectorIndexes firstIndex] by:_sectorsToExtract.firstSector];
			[allMismatchedSectors addObject:nonMatchingSectors];
		}
		
		// Compare to the synthesized tracks
		for(NSURL *synthesizedTrackURL in _synthesizedTrackURLs) {
			
			NSIndexSet *nonMatchingSectorIndexes = compareFilesForNonMatchingSectors(operation.URL, synthesizedTrackURL);
			
			// Convert from sector indexes to sector numbers				
			NSMutableIndexSet *nonMatchingSectors = [nonMatchingSectorIndexes mutableCopy];
			[nonMatchingSectors shiftIndexesStartingAtIndex:[nonMatchingSectorIndexes firstIndex] by:_sectorsToExtract.firstSector];
			[allMismatchedSectors addObject:nonMatchingSectors];
		}
	}
	
	// Iterate through each synthesized track
	for(NSUInteger trackIndex = 0; trackIndex < [_synthesizedTrackURLs count]; ++trackIndex) {
		
		NSURL *synthesizedTrackURL = [_synthesizedTrackURLs objectAtIndex:trackIndex];
		
		// Compare to the whole extraction operations
		for(ExtractionOperation *operation in _wholeExtractions) {
			
			// Use C2 if specified
			if(useC2 && (operation.useC2 != useC2))
				continue;
			
			NSIndexSet *nonMatchingSectorIndexes = compareFilesForNonMatchingSectors(synthesizedTrackURL, operation.URL);
						
			// Convert from sector indexes to sector numbers				
			NSMutableIndexSet *nonMatchingSectors = [nonMatchingSectorIndexes mutableCopy];
			[nonMatchingSectors shiftIndexesStartingAtIndex:[nonMatchingSectorIndexes firstIndex] by:_sectorsToExtract.firstSector];
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
			[nonMatchingSectors shiftIndexesStartingAtIndex:[nonMatchingSectorIndexes firstIndex] by:_sectorsToExtract.firstSector];
			[allMismatchedSectors addObject:nonMatchingSectors];
		}
	}
	
	NSMutableIndexSet *nonMatchingSectors = [NSMutableIndexSet indexSet];
	
	for(NSIndexSet *mismatchedSectors in allMismatchedSectors)
		[nonMatchingSectors addIndexes:mismatchedSectors];
	
	return [nonMatchingSectors copy];
}

- (NSURL *) outputURL
{
	return [self outputURLUsingC2:[self.driveInformation.useC2 boolValue]];
}

- (NSURL *) outputURLUsingC2:(BOOL)useC2
{
	// For a track to be successfully extracted, it must match self.requiredMatches
	// other track extractions as determined by SHA1 comparisons

	// A track can be generated in two ways- via a single extraction operation or 
	// synthesized sector-by-sector, so for completeness it is necessary to compare them all
	
	// First iterate through all the whole extractions and compare to the other whole extractions
	// and synthesized tracks
	for(NSUInteger trackIndex = 0; trackIndex < [_wholeExtractions count]; ++trackIndex) {
		
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
			return operation.URL;
	}
		
	// If a match wasn't yet made, iterate through each synthesized track
	for(NSUInteger trackIndex = 0; trackIndex < [_synthesizedTrackURLs count]; ++trackIndex) {
		
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

- (NSURL *) bestGuessURL
{
	return [self bestGuessURLUsingC2:[self.driveInformation.useC2 boolValue]];
}

- (NSURL *) bestGuessURLUsingC2:(BOOL)useC2
{
	// Create the output file
	NSURL *outputURL = temporaryURLWithExtension(@"wav");
	
	NSError *error = nil;
	if(!createCDDAFileAtURL(outputURL, &error)) {
		[self presentError:error 
			modalForWindow:[[self view] window] 
				  delegate:self 
		didPresentSelector:@selector(didPresentErrorWithRecovery:contextInfo:) 
			   contextInfo:NULL];
		
		return nil;
	}

	ExtractedAudioFile *outputFile = [ExtractedAudioFile openFileForReadingAndWritingAtURL:outputURL error:&error];
	if(!outputFile)
		return nil;
	
	// Iterate through each sector and save the audio
	// This could probably be improved
	for(NSUInteger sector = [_sectorsToExtract firstSector]; sector <= [_sectorsToExtract lastSector]; ++sector) {

		// First try to honor the C2 error flags
		NSData *sectorData = [self nonInterpolatedDataForSector:sector requiredMatches:0 useC2:useC2];
		if(!sectorData)
			sectorData = [self interpolatedDataForSector:sector requiredMatches:0 useC2:useC2];
		
		// If C2 is enabled and failed, try to get something without C2
		if(useC2 && !sectorData)
			sectorData = [self nonInterpolatedDataForSector:sector requiredMatches:0 useC2:NO];
		if(useC2 && !sectorData)
			sectorData = [self interpolatedDataForSector:sector requiredMatches:0 useC2:NO];
		
		// Even if no audio was returned, don't fail
		if(sectorData)
			[outputFile setAudioData:sectorData forSector:[_sectorsToExtract indexForSector:sector] error:&error];
		else
			[[Logger sharedLogger] logMessageWithLevel:eLogMessageLevelDebug format:@"No audio returned for sector %i", sector];
	}
	
	[outputFile closeFile];
	
	return outputURL;
}

- (BOOL) verifyTrackWithAccurateRip:(NSURL *)inputURL
{
	NSParameterAssert(nil != inputURL);
	
	NSRange trackAudioRange = NSMakeRange(MAXIMUM_OFFSET_TO_CHECK_IN_SECTORS - _sectorsOfSilenceToPrepend, _currentTrack.sectorCount);
	
	// Calculate the AccurateRip checksums for the track
	NSData *trackAccurateRipChecksumsData = calculateAccurateRipChecksumsForTrackInFile(inputURL, 
																						trackAudioRange, 
																						[self.compactDisc.firstSession.firstTrack.number isEqualToNumber:_currentTrack.number],
																						[self.compactDisc.firstSession.lastTrack.number isEqualToNumber:_currentTrack.number],
																						MAXIMUM_OFFSET_TO_CHECK_IN_SECTORS,
																						YES);
	
	// Only bother checking for AR matches if this disc is present in AR and checksum calculations were successful
	if(trackAccurateRipChecksumsData && [self.compactDisc.accurateRipDiscs count]) {
		const uint32_t *trackAccurateRipChecksums = [trackAccurateRipChecksumsData bytes];
		NSUInteger checksumsCount = [trackAccurateRipChecksumsData length] / sizeof(uint32_t);
		
		// The checksums are arranged in the array from [-maximumOffsetInFrames, +maximumOffsetInFrames], so the item at
		// maximumOffsetInFrames is the checksum for offset 0, the track's primary checksum
		NSUInteger maximumOffsetInFrames = (checksumsCount - 1) / 2;
		NSUInteger trackPrimaryAccurateRipChecksum = trackAccurateRipChecksums[maximumOffsetInFrames];
		
		// Regardless of any C2 or other errors, a track is ready for encoding if it matches a track in the AR database	
		for(AccurateRipDiscRecord *accurateRipDisc in self.compactDisc.accurateRipDiscs) {
			AccurateRipTrackRecord *accurateRipTrack = [accurateRipDisc trackNumber:[_currentTrack.number unsignedIntegerValue]];
			
			if(!accurateRipTrack)
				continue;
			
			// The track matches, so queue it for encoding
			if([accurateRipTrack.checksum unsignedIntegerValue] == trackPrimaryAccurateRipChecksum) {
				[[Logger sharedLogger] logMessageWithLevel:eLogMessageLevelDebug format:@"Primary Accurate Rip checksum (%.8x) matches", trackPrimaryAccurateRipChecksum];
				
				BOOL trackSaved = [self saveTrackFromURL:inputURL
									 accurateRipChecksum:trackPrimaryAccurateRipChecksum 
							  accurateRipConfidenceLevel:accurateRipTrack.confidenceLevel];
				
				if(trackSaved)
					return YES;
			}
		}
		
		// Check the remaining offsets
		for(NSInteger currentOffset = -maximumOffsetInFrames; currentOffset <= (NSInteger)maximumOffsetInFrames; ++currentOffset) {
			NSUInteger trackOffsetAccurateRipChecksum = trackAccurateRipChecksums[currentOffset + maximumOffsetInFrames];
			
			for(AccurateRipDiscRecord *accurateRipDisc in self.compactDisc.accurateRipDiscs) {
				AccurateRipTrackRecord *accurateRipTrack = [accurateRipDisc trackNumber:[_currentTrack.number unsignedIntegerValue]];
				
				if(!accurateRipTrack)
					continue;
				
				if([accurateRipTrack.checksum unsignedIntegerValue] == trackOffsetAccurateRipChecksum) {
					[[Logger sharedLogger] logMessageWithLevel:eLogMessageLevelDebug format:@"Alternate Accurate Rip checksum (%.8x) matches (offset %i)",trackOffsetAccurateRipChecksum, currentOffset];
					
					BOOL trackSaved = [self saveTrackFromURL:inputURL 
										 accurateRipChecksum:trackPrimaryAccurateRipChecksum 
								  accurateRipConfidenceLevel:accurateRipTrack.confidenceLevel
						accurateRipAlternatePressingChecksum:trackOffsetAccurateRipChecksum 
						  accurateRipAlternatePressingOffset:[NSNumber numberWithInteger:currentOffset]];
					
					if(trackSaved)
						return YES;
				}
			}
		}
	}
	// If Accurate Rip checksum calculations failed, log the error
	else if(!trackAccurateRipChecksumsData)
		[[Logger sharedLogger] logMessage:@"Accurate Rip checksum calculations failed"];
	
	return NO;
}

- (BOOL) saveSector:(NSUInteger)sector sectorData:(NSData *)sectorData
{
	NSParameterAssert(nil != sectorData);
	
	NSError *error = nil;
	
	// Create the output file if it doesn't exist
	if(!_synthesizedTrackURL) {
		_synthesizedTrackURL = temporaryURLWithExtension(@"wav");
		
		if(!createCDDAFileAtURL(_synthesizedTrackURL, &error)) {
			[self presentError:error 
				modalForWindow:[[self view] window] 
					  delegate:self 
			didPresentSelector:@selector(didPresentErrorWithRecovery:contextInfo:) 
				   contextInfo:NULL];
			
			return NO;
		}
	}

	ExtractedAudioFile *synthesizedTrack = [ExtractedAudioFile openFileForReadingAndWritingAtURL:_synthesizedTrackURL error:&error];
	if(!synthesizedTrack)
		return NO;
	
	[synthesizedTrack setAudioData:sectorData forSector:[_sectorsToExtract indexForSector:sector] error:&error];
	
	[synthesizedTrack closeFile];
	
	return YES;
}

- (BOOL) saveSectors:(NSIndexSet *)sectors fromOperation:(ExtractionOperation *)operation
{
	NSParameterAssert(nil != sectors);
	NSParameterAssert(nil != operation);
	
	// Create the output file if it doesn't exist
	if(!_synthesizedTrackURL) {
		_synthesizedTrackURL = temporaryURLWithExtension(@"wav");
		
		NSError *error = nil;
		if(!createCDDAFileAtURL(_synthesizedTrackURL, &error)) {
			[self presentError:error 
				modalForWindow:[[self view] window] 
					  delegate:self 
			didPresentSelector:@selector(didPresentErrorWithRecovery:contextInfo:) 
				   contextInfo:NULL];
			
			return NO;
		}
	}
	
	// Convert the absolute sector numbers to indexes within the extracted audio
	NSUInteger firstSectorInInputFile = operation.sectors.firstSector;
	NSUInteger firstSectorInOutputFile = _sectorsToExtract.firstSector;
	
	// Copy and save the specified sectors, combining ranges to minimize reads
	NSUInteger firstIndex = NSNotFound;
	NSUInteger latestIndex = NSNotFound;
	NSUInteger sectorIndex = [sectors firstIndex];
	
	for(;;) {
		// Last sector
		if(NSNotFound == sectorIndex) {
			if(NSNotFound != firstIndex) {
				if(firstIndex == latestIndex) {
					if(!copySectorsFromURLToURL(operation.URL, NSMakeRange(firstIndex - firstSectorInInputFile, 1), _synthesizedTrackURL, firstIndex - firstSectorInOutputFile))
						return NO;
				}
				else {
					NSUInteger sectorCount = latestIndex - firstIndex + 1;
					if(!copySectorsFromURLToURL(operation.URL, NSMakeRange(firstIndex - firstSectorInInputFile, sectorCount), _synthesizedTrackURL, firstIndex - firstSectorInOutputFile))
						return NO;
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
					if(!copySectorsFromURLToURL(operation.URL, NSMakeRange(firstIndex - firstSectorInInputFile, 1), _synthesizedTrackURL, firstIndex - firstSectorInOutputFile))
						return NO;
				}
				else {
					NSUInteger sectorCount = latestIndex - firstIndex + 1;
					if(!copySectorsFromURLToURL(operation.URL, NSMakeRange(firstIndex - firstSectorInInputFile, sectorCount), _synthesizedTrackURL, firstIndex - firstSectorInOutputFile))
						return NO;
				}
			}
			
			firstIndex = sectorIndex;
			latestIndex = sectorIndex;
		}
		
		sectorIndex = [sectors indexGreaterThanIndex:sectorIndex];
	}

	return YES;
}

- (BOOL) saveTrackFromURL:(NSURL *)trackWithCushionSectorsURL
{
	return [self saveTrackFromURL:trackWithCushionSectorsURL copyVerified:YES];
}

- (BOOL) saveTrackFromURL:(NSURL *)trackWithCushionSectorsURL copyVerified:(BOOL)copyVerified
{
	NSParameterAssert(nil != trackWithCushionSectorsURL);
	
	NSError *error = nil;
	
	// Create an output file containing only the track audio (strip off the extra sectors used for AR calculations)
	NSURL *trackURL = [self generateOutputFileForURL:trackWithCushionSectorsURL error:&error];
	if(!trackURL)
		return NO;
	
	// Create and save the track extraction record
	TrackExtractionRecord *extractionRecord = [self createTrackExtractionRecordForFileURL:trackURL];
	if(!extractionRecord)
		return NO;
	
	extractionRecord.copyVerified = [NSNumber numberWithBool:copyVerified];
	
	[self addTrackExtractionRecord:extractionRecord];
	
	return YES;
}

- (BOOL) saveTrackFromURL:(NSURL *)trackWithCushionSectorsURL accurateRipChecksum:(NSUInteger)accurateRipChecksum accurateRipConfidenceLevel:(NSNumber *)accurateRipConfidenceLevel
{
	return [self saveTrackFromURL:trackWithCushionSectorsURL 
			  accurateRipChecksum:accurateRipChecksum 
	   accurateRipConfidenceLevel:accurateRipConfidenceLevel
accurateRipAlternatePressingChecksum:0
accurateRipAlternatePressingOffset:nil];
}

- (BOOL) saveTrackFromURL:(NSURL *)trackWithCushionSectorsURL accurateRipChecksum:(NSUInteger)accurateRipChecksum accurateRipConfidenceLevel:(NSNumber *)accurateRipConfidenceLevel accurateRipAlternatePressingChecksum:(NSUInteger)accurateRipAlternatePressingChecksum accurateRipAlternatePressingOffset:(NSNumber *)accurateRipAlternatePressingOffset
{
	NSParameterAssert(nil != trackWithCushionSectorsURL);
		
	NSError *error = nil;
	
	// Create an output file containing only the track audio (strip off the extra sectors used for AR calculations)
	NSURL *trackURL = [self generateOutputFileForURL:trackWithCushionSectorsURL error:&error];
	if(!trackURL)
		return NO;
	
	// Create and save the track extraction record
	TrackExtractionRecord *extractionRecord = [self createTrackExtractionRecordForFileURL:trackURL
																	  accurateRipChecksum:accurateRipChecksum
															   accurateRipConfidenceLevel:accurateRipConfidenceLevel
													 accurateRipAlternatePressingChecksum:accurateRipAlternatePressingChecksum 
													   accurateRipAlternatePressingOffset:accurateRipAlternatePressingOffset];
	if(!extractionRecord)
		return NO;
	
	[self addTrackExtractionRecord:extractionRecord];
	
	return YES;
}

@end
