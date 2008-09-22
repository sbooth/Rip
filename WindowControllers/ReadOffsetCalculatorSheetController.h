/*
 *  Copyright (C) 2008 Stephen F. Booth <me@sbooth.org>
 *  All Rights Reserved
 */

#import <Cocoa/Cocoa.h>
#include <DiskArbitration/DiskArbitration.h>

@class CompactDisc, DriveInformation;
@class AccurateRipQueryOperation, ExtractionOperation, ReadOffsetCalculationOperation;

@interface ReadOffsetCalculatorSheetController : NSWindowController
{
	IBOutlet NSProgressIndicator *_accurateRipQueryProgressIndicator;
	IBOutlet NSProgressIndicator *_extractionProgressIndicator;
	IBOutlet NSProgressIndicator *_offsetCalculationProgressIndicator;

	IBOutlet NSTextField *_accurateRipQueryTextField;
	IBOutlet NSTextField *_extractionTextField;
	IBOutlet NSTextField *_offsetCalculationTextField;

	IBOutlet NSTextField *_suggestedOffsetTextField;
	IBOutlet NSArrayController *_possibleOffsetsArrayController;
	
	IBOutlet NSButton *_possibleOffsetsViewDisclosureButton;
	IBOutlet NSView *_possibleOffsetsView;
	
@private
	DADiskRef _disk;
	CompactDisc *_compactDisc;
	DriveInformation *_driveInformation;
	NSOperationQueue *_operationQueue;
	AccurateRipQueryOperation *_accurateRipQueryOperation;
	ExtractionOperation *_extractionOperation;
	ReadOffsetCalculationOperation *_offsetCalculationOperation;
	BOOL _possibleOffsetsShown;
}

// ========================================
// Properties
// ========================================
@property (assign) DADiskRef disk;
@property (readonly, assign) CompactDisc * compactDisc;
@property (readonly, assign) DriveInformation * driveInformation;

@property (readonly) NSOperationQueue * operationQueue;

@property (readonly, assign) AccurateRipQueryOperation * accurateRipQueryOperation;
@property (readonly, assign) ExtractionOperation * extractionOperation;
@property (readonly, assign) ReadOffsetCalculationOperation * offsetCalculationOperation;

@property (readonly, assign) BOOL possibleOffsetsShown;

@property (readonly) NSManagedObjectContext * managedObjectContext;
@property (readonly) id managedObjectModel;

// ========================================
// Action Methods
// ========================================
- (IBAction) determineDriveOffset:(id)sender;

- (IBAction) acceptSuggestedOffset:(id)sender;
- (IBAction) cancel:(id)sender;

- (IBAction) togglePossibleOffsetsShown:(id)sender;
- (IBAction) useSelectedOffset:(id)sender;

@end
