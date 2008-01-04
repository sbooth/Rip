/*
 *  Copyright (C) 2008 Stephen F. Booth <me@sbooth.org>
 *  All Rights Reserved
 */

#import <Cocoa/Cocoa.h>

@class CompactDisc;

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

// ========================================
// KVC key names for the query results
// ========================================
extern NSString * const		kMusicDatabaseTracksKey;		// NSArray * of NSDictionary *

// ========================================
// Class providing a generic interface to an online music database
// such as FreeDB or MusicBrainz
// ========================================
@interface MusicDatabase : NSObject
{
	CompactDisc *_compactDisc;
	NSMutableArray *_queryResults;
}

@property (copy) CompactDisc * compactDisc;
@property (readonly) NSArray * queryResults;

- (BOOL) performQuery:(NSError **)error;

@end
