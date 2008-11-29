/*
 *  Copyright (C) 2008 Stephen F. Booth <me@sbooth.org>
 *  All Rights Reserved
 */

#import <Cocoa/Cocoa.h>

// ========================================
// KVC key names for the metadata dictionary
// ========================================
extern NSString * const		kMetadataTitleKey;					// NSString *
extern NSString * const		kMetadataAlbumTitleKey;				// NSString *
extern NSString * const		kMetadataArtistKey;					// NSString *
extern NSString * const		kMetadataAlbumArtistKey;			// NSString *
extern NSString * const		kMetadataGenreKey;					// NSString *
extern NSString * const		kMetadataComposerKey;				// NSString *
extern NSString * const		kMetadataReleaseDateKey;			// NSString *
extern NSString * const		kMetadataCompilationKey;			// NSNumber *
extern NSString * const		kMetadataTrackNumberKey;			// NSNumber *
extern NSString * const		kMetadataTrackTotalKey;				// NSNumber *
extern NSString * const		kMetadataDiscNumberKey;				// NSNumber *
extern NSString * const		kMetadataDiscTotalKey;				// NSNumber *
extern NSString * const		kMetadataLyricsKey;					// NSString *
extern NSString * const		kMetadataCommentKey;				// NSString *
extern NSString * const		kMetadataISRCKey;					// NSString *
extern NSString * const		kMetadataMCNKey;					// NSString *
extern NSString * const		kMetadataMusicBrainzIDKey;			// NSString *

// ========================================
// This value will only be present in imageMetadata
// ========================================
extern NSString * const		kTrackMetadataArrayKey;				// NSArray * of NSDictionary *

// ========================================
// An NSOperation subclass that defines the interface to be implemented by encoders
// desiring to post-process their output
// ========================================
@interface EncodingPostProcessingOperation : NSOperation
{
@protected
	BOOL _isImage;
	NSURL *_imageURL;
	NSDictionary *_imageMetadata;
	NSURL *_cueSheetURL;
	NSArray *_trackURLs;
	NSArray *_trackMetadata;
	NSDictionary *_settings;
	NSError *_error;
}

// YES if post-processing a disc image, NO otherwise
@property (assign) BOOL isImage;

// Properties set if processing a disc image
@property (copy) NSURL * imageURL;
@property (copy) NSDictionary * imageMetadata;
@property (copy) NSURL * cueSheetURL;

// Properties set if processing individual tracks
@property (copy) NSArray * trackURLs;
@property (copy) NSArray * trackMetadata;

// General properties
@property (copy) NSDictionary * settings;
@property (copy) NSError * error;

// Optional properties
@property (readonly) NSNumber * progress;

@end
