/*
 *  Copyright (C) 2008 Stephen F. Booth <me@sbooth.org>
 *  All Rights Reserved
 */

#import <Cocoa/Cocoa.h>
#include <DiskArbitration/DiskArbitration.h>

@class CompactDisc, DriveInformation;

@interface DriveOffsetCalculatorWindowController : NSWindowController
{
	IBOutlet NSProgressIndicator *_accurateRipQueryProgressIndicator;
	IBOutlet NSProgressIndicator *_extractionProgressIndicator;
	IBOutlet NSProgressIndicator *_offsetCalculationProgressIndicator;

	IBOutlet NSTextField *_accurateRipQueryTextField;
	IBOutlet NSTextField *_extractionTextField;
	IBOutlet NSTextField *_offsetCalculationTextField;

	IBOutlet NSArrayController *_possibleOffsetsArrayController;

@private
	DADiskRef _disk;
	CompactDisc *_compactDisc;
	DriveInformation *_driveInformation;
	NSOperationQueue *_operationQueue;
}

// ========================================
// Properties
// ========================================
@property (assign) DADiskRef disk;
@property (readonly, assign) CompactDisc * compactDisc;
@property (readonly, assign) DriveInformation * driveInformation;

@property (readonly) NSOperationQueue * operationQueue;

@property (readonly) NSManagedObjectContext * managedObjectContext;
@property (readonly) id managedObjectModel;

// ========================================
// Action Methods
// ========================================
- (IBAction) determineDriveOffset:(id)sender;

- (IBAction) acceptOffset:(id)sender;
- (IBAction) cancel:(id)sender;

@end
