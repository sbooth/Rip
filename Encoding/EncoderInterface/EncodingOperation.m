/*
 *  Copyright (C) 2008 Stephen F. Booth <me@sbooth.org>
 *  All Rights Reserved
 */

#import "EncodingOperation.h"

// ========================================
// KVC key names for the metadata dictionary
// ========================================
NSString * const	kMetadataTitleKey						= @"title";
NSString * const	kMetadataAlbumTitleKey					= @"albumTitle";
NSString * const	kMetadataArtistKey						= @"artist";
NSString * const	kMetadataAlbumArtistKey					= @"albumArtist";
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
NSString * const	kTrackMetadataArrayKey					= @"trackMetadataArray";

@implementation EncodingOperation

@synthesize inputURL = _inputURL;
@synthesize outputURL = _outputURL;
@synthesize settings = _settings;
@synthesize metadata = _metadata;
@synthesize error = _error;

@dynamic progress;

@end
