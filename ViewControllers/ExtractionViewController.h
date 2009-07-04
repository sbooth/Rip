/*
 *  Copyright (C) 2008 - 2009 Stephen F. Booth <me@sbooth.org>
 *  All Rights Reserved
 */

#import <Cocoa/Cocoa.h>
#include <DiskArbitration/DiskArbitration.h>

#include "replaygain_analysis.h"

@class SectorRange, CompactDisc, DriveInformation;
@class ExtractionOperation;
@class TrackDescriptor;
@class ImageExtractionRecord;

// ========================================
// The number of sectors which will be scanned during offset verification
// ========================================
#define MAXIMUM_OFFSET_TO_CHECK_IN_SECTORS 3

// ========================================
// The minimum size (in bytes) of blocks to re-read from the disc
// ========================================
#define MINIMUM_DISC_READ_SIZE (2048 * 1024)

// ========================================
// Enum for extraction modes
// ========================================
enum _eExtractionMode {
	eExtractionModeIndividualTracks = 1,
	eExtractionModeImage = 2
};
typedef enum _eExtractionMode eExtractionMode;

// ========================================
// Context objects for observeValueForKeyPath:ofObject:change:context:
// ========================================
extern NSString * const kMCNDetectionKVOContext;
extern NSString * const kISRCDetectionKVOContext;
extern NSString * const kPregapDetectionKVOContext;
extern NSString * const kAudioExtractionKVOContext;

// ========================================
// An NSViewController subclass for customizing the extraction
// of one or more tracks from a CD
// ========================================
@interface ExtractionViewController : NSViewController
{
	IBOutlet NSProgressIndicator *_progressIndicator;
	IBOutlet NSTextField *_statusTextField;
	IBOutlet NSTextField *_detailedStatusTextField;
	
	IBOutlet NSArrayController *_tracksArrayController;
	IBOutlet NSTableView *_tracksTable;

@private
	__strong DADiskRef _disk;
	NSSet *_trackIDs;
	
	CompactDisc *_compactDisc;
	DriveInformation *_driveInformation;
	NSManagedObjectContext *_managedObjectContext;
	
	NSMutableArray *_activeTimers;
	NSOperationQueue *_operationQueue;
	
	TrackDescriptor *_currentTrack;
	NSMutableSet *_trackIDsRemaining;
	
	NSMutableArray *_wholeExtractions;
	NSMutableArray *_partialExtractions;
	NSMutableIndexSet *_sectorsNeedingVerification;

	NSURL *_synthesizedTrackURL;
	NSUInteger _sectorsOfSilenceToPrepend;
	NSUInteger _sectorsOfSilenceToAppend;
	SectorRange *_sectorsToExtract;
	
	NSMutableArray *_synthesizedTrackURLs;
	NSMutableDictionary *_synthesizedTrackSHAs;

	NSUInteger _requiredSectorMatches;
	NSUInteger _requiredTrackMatches;
	NSUInteger _retryCount;
	NSUInteger _maxRetries;
	BOOL _allowExtractionFailure;
	
	eExtractionMode _extractionMode;
		
	ImageExtractionRecord *_imageExtractionRecord;
	NSMutableSet *_trackExtractionRecords;
	NSMutableSet *_failedTrackIDs;
	
	struct replaygain_t _rg;
	
	// Properties maintained for UI
	NSMutableSet *_tracks;
	NSTimeInterval _secondsElapsed;
	NSTimeInterval _estimatedSecondsRemaining;
	NSUInteger _c2ErrorCount;
}

// ========================================
// Properties
@property (assign) DADiskRef disk;
@property (copy) NSSet * trackIDs;

// TODO: currentTrackID??
//@property (readonly, assign) TrackDescriptor * currentTrack;

@property (assign) NSUInteger maxRetries;
@property (assign) NSUInteger requiredSectorMatches;
@property (assign) NSUInteger requiredTrackMatches;
@property (assign) BOOL allowExtractionFailure;

@property (assign) eExtractionMode extractionMode;

@property (readonly, assign) CompactDisc * compactDisc;
@property (readonly, assign) DriveInformation * driveInformation;
@property (readonly, assign) NSManagedObjectContext * managedObjectContext;

@property (readonly, assign) NSOperationQueue * operationQueue;

@property (readonly) ImageExtractionRecord * imageExtractionRecord;
@property (readonly) NSSet * trackExtractionRecords;
@property (readonly) NSSet * failedTrackIDs;

// UI properties
@property (readonly, assign) NSTimeInterval secondsElapsed;
@property (readonly, assign) NSTimeInterval estimatedSecondsRemaining;
@property (readonly, assign) NSUInteger c2ErrorCount;

// ========================================
// The meat & potatoes
- (IBAction) extract:(id)sender;
- (IBAction) skipTrack:(id)sender;

// ========================================
// Action methods
- (IBAction) cancel:(id)sender;

@end
