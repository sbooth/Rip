/*
 *  Copyright (C) 2008 - 2009 Stephen F. Booth <me@sbooth.org>
 *  All Rights Reserved
 */

#import <Cocoa/Cocoa.h>
#include <DiskArbitration/DiskArbitration.h>

@class CompactDisc, DriveInformation, AccurateRipDiscRecord;
@class ExtractionOperation, ExtractedAudioFile;
@class TrackDescriptor;
@class ImageExtractionRecord;

// ========================================
// Enum for extraction modes
// ========================================
enum _eExtractionMode {
	eExtractionModeIndividualTracks = 1,
	eExtractionModeImage = 2
};
typedef enum _eExtractionMode eExtractionMode;

// ========================================
// An NSViewController subclass for customizing the extraction
// of one or more tracks from a CD
//
// The general extraction strategy looks like:
//  - Extract the entire track (copy)
//  - Compare
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
	
	NSMutableSet *_trackIDsRemaining;
	
	ExtractionOperation *_copyOperation;
	ExtractionOperation *_verificationOperation;
	
	NSMutableArray *_partialExtractions;
	NSMutableIndexSet *_sectorsNeedingVerification;
	
	NSMutableArray *_encodingOperations;
	
	NSUInteger _requiredMatches;
	NSUInteger _retryCount;
	NSUInteger _maxRetries;
	
	eExtractionMode _extractionMode;
	
	ExtractedAudioFile *_synthesizedTrack;
	NSURL *_synthesizedCopyURL;
	
	ImageExtractionRecord *_imageExtractionRecord;
	NSMutableSet *_trackExtractionRecords;
	NSMutableSet *_failedTrackIDs;
	
	// Properties maintained for UI
	TrackDescriptor *_currentTrack;
	NSMutableSet *_tracks;
	NSTimeInterval _secondsElapsed;
	NSTimeInterval _estimatedSecondsRemaining;
	NSUInteger _c2ErrorCount;
}

// ========================================
// Properties
@property (assign) DADiskRef disk;
@property (copy) NSSet * trackIDs;

@property (assign) NSUInteger maxRetries;
@property (assign) NSUInteger requiredMatches;

@property (assign) eExtractionMode extractionMode;

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

// ========================================
// Action methods
- (IBAction) cancel:(id)sender;

@end
