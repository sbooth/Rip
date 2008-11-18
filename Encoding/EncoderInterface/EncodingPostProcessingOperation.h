/*
 *  Copyright (C) 2008 Stephen F. Booth <me@sbooth.org>
 *  All Rights Reserved
 */

#import <Cocoa/Cocoa.h>

// ========================================
// KVC key names for the metadata dictionary
// ========================================
extern NSString * const		kMetadataTitleKey;
extern NSString * const		kMetadataAlbumTitleKey;
extern NSString * const		kMetadataArtistKey;
extern NSString * const		kMetadataAlbumArtistKey;
extern NSString * const		kMetadataGenreKey;
extern NSString * const		kMetadataComposerKey;
extern NSString * const		kMetadataReleaseDateKey;
extern NSString * const		kMetadataCompilationKey;
extern NSString * const		kMetadataTrackNumberKey;
extern NSString * const		kMetadataTrackTotalKey;
extern NSString * const		kMetadataDiscNumberKey;
extern NSString * const		kMetadataDiscTotalKey;
extern NSString * const		kMetadataLyricsKey;
extern NSString * const		kMetadataCommentKey;
extern NSString * const		kMetadataISRCKey;
extern NSString * const		kMetadataMCNKey;
extern NSString * const		kMetadataMusicBrainzIDKey;

// ========================================
// An NSOperation subclass that defines the interface to be implemented by encoders
// desiring to post-process their output
// ========================================
@interface EncodingPostProcessingOperation : NSOperation
{
@protected
	NSArray *_URLs;
	NSArray *_metadata;
	NSDictionary *_settings;
	NSError *_error;
}

@property (copy) NSArray * URLs;
@property (copy) NSArray * metadata;
@property (copy) NSDictionary * settings;
@property (copy) NSError * error;

// Optional properties
@property (readonly) NSNumber * progress;

@end
