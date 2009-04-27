/*
 *  Copyright (C) 2008 - 2009 Stephen F. Booth <me@sbooth.org>
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
extern NSString * const		kMetadataMusicBrainzAlbumIDKey;		// NSString *
extern NSString * const		kMetadataMusicBrainzTrackIDKey;		// NSString *
extern NSString * const		kMetadataAdditionalMetadataKey;		// NSDictionary *

extern NSString * const		kReplayGainReferenceLoudnessKey;	// NSNumber *
extern NSString * const		kReplayGainTrackGainKey;			// NSNumber *
extern NSString * const		kReplayGainTrackPeakKey;			// NSNumber *
extern NSString * const		kReplayGainAlbumGainKey;			// NSNumber *
extern NSString * const		kReplayGainAlbumPeakKey;			// NSNumber *

extern NSString * const		kAlbumArtFrontCoverKey;				// NSURL *

// ========================================
// This value will only be present if inputURL represents a disc image
// ========================================
extern NSString * const		kTrackMetadataArrayKey;				// NSArray * of NSDictionary *

// ========================================
// An NSOperation subclass that defines the interface to be implemented by encoders
// ========================================
@interface EncodingOperation : NSOperation
{
@protected
	NSURL *_inputURL;
	NSURL *_outputURL;
	NSDictionary *_settings;
	NSDictionary *_metadata;
	NSError *_error;
}

@property (copy) NSURL * inputURL;
@property (copy) NSURL * outputURL;
@property (copy) NSDictionary * settings;
@property (copy) NSDictionary * metadata;
@property (copy) NSError * error;

// Optional properties
@property (readonly) NSNumber * progress;

@end
