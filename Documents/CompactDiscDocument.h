/*
 *  Copyright (C) 2007 Stephen F. Booth <me@sbooth.org>
 *  All Rights Reserved
 */

#import <Cocoa/Cocoa.h>
#include <DiskArbitration/DiskArbitration.h>

// ========================================
// KVC key names for the metadata dictionaries
// ========================================
extern NSString * const		kMetadataTitleKey;
extern NSString * const		kMetadataAlbumTitleKey;
extern NSString * const		kMetadataArtistKey;
extern NSString * const		kMetadataAlbumArtistKey;
extern NSString * const		kMetadataGenreKey;
extern NSString * const		kMetadataComposerKey;
extern NSString * const		kMetadataDateKey;
extern NSString * const		kMetadataCompilationKey;
extern NSString * const		kMetadataTrackNumberKey;
extern NSString * const		kMetadataTrackTotalKey;
extern NSString * const		kMetadataDiscNumberKey;
extern NSString * const		kMetadataDiscTotalKey;
extern NSString * const		kMetadataCommentKey;
extern NSString * const		kMetadataISRCKey;
extern NSString * const		kMetadataMCNKey;
extern NSString * const		kMetadataBPMKey;
extern NSString * const		kMetadataMusicDNSPUIDKey;
extern NSString * const		kMetadataMusicBrainzIDKey;

@class CompactDisc, AccurateRipDisc, DriveInformation;

@interface CompactDiscDocument : NSPersistentDocument
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

- (IBAction) ejectDisc:(id)sender;

@end
