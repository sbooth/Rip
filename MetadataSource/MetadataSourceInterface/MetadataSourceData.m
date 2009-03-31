/*
 *  Copyright (C) 2009 Stephen F. Booth <me@sbooth.org>
 *  All Rights Reserved
 */

#import "MetadataSourceData.h"

// ========================================
// KVC key names for the metadata dictionaries
// ========================================
NSString * const	kMetadataTitleKey						= @"title";
NSString * const	kMetadataArtistKey						= @"artist";
NSString * const	kMetadataGenreKey						= @"genre";
NSString * const	kMetadataComposerKey					= @"composer";
NSString * const	kMetadataReleaseDateKey					= @"date";
NSString * const	kMetadataCompilationKey					= @"compilation";
NSString * const	kMetadataTrackNumberKey					= @"trackNumber";
NSString * const	kMetadataTrackTotalKey					= @"trackTotal";
NSString * const	kMetadataDiscNumberKey					= @"discNumber";
NSString * const	kMetadataDiscTotalKey					= @"discTotal";
NSString * const	kMetadataLyricsKey						= @"lyrics";
NSString * const	kMetadataCommentKey						= @"comment";
NSString * const	kMetadataISRCKey						= @"ISRC";
NSString * const	kMetadataMCNKey							= @"MCN";
NSString * const	kMetadataMusicBrainzIDKey				= @"MusicBrainzID";
NSString * const	kMetadataAdditionalMetadataKey			= @"additionalMetadata";
NSString * const	kAlbumArtFrontCoverKey					= @"albumArtFrontCover";
NSString * const	kTrackMetadataArrayKey					= @"tracks";

@implementation MetadataSourceData

// ========================================
// Properties
@synthesize discTOC = _discTOC;
@synthesize freeDBDiscID = _freeDBDiscID;
@synthesize musicBrainzDiscID = _musicBrainzDiscID;
@synthesize settings = _settings;
@synthesize metadata = _metadata;

@end
