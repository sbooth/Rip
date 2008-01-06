/*
 *  Copyright (C) 2007 Stephen F. Booth <me@sbooth.org>
 *  All Rights Reserved
 */

#import <Cocoa/Cocoa.h>
#include <DiskArbitration/DiskArbitration.h>

@class CompactDisc, AccurateRipDisc, DriveInformation;

@interface CompactDiscWindowController : NSWindowController
{
	IBOutlet NSArrayController *_trackController;
	IBOutlet NSObjectController *_driveInformationController;
	
	DADiskRef _disk;
	CompactDisc *_compactDisc;
	AccurateRipDisc *_accurateRipDisc;
	DriveInformation *_driveInformation;
	
	NSMutableArray *_tracks;
	NSMutableDictionary *_metadata;
	
	NSOperationQueue *_compactDiscOperationQueue;
	NSOperationQueue *_encodingQueue;
}

@property (readonly) NSArrayController * trackController;
@property (readonly) NSObjectController * driveInformationController;
@property (readonly) NSOperationQueue * compactDiscOperationQueue;
@property (readonly) NSOperationQueue * encodingQueue;

// ========================================
// Properties
// ========================================
@property (assign) DADiskRef disk;
@property (readonly, assign) CompactDisc * compactDisc;
@property (readonly, assign) AccurateRipDisc * accurateRipDisc;
@property (readonly, assign) DriveInformation * driveInformation;
@property (readonly) NSMutableDictionary * metadata;
@property (readonly) NSArray * tracks;

// ========================================
// Action Methods
// ========================================
- (IBAction) copySelectedTracks:(id)sender;
- (IBAction) copyImage:(id)sender;

- (IBAction) detectPreGaps:(id)sender;

- (IBAction) queryMusicDatabase:(id)sender;

- (IBAction) ejectDisc:(id)sender;

@end
