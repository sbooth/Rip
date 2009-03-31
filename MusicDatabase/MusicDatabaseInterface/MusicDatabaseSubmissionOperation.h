/*
 *  Copyright (C) 2009 Stephen F. Booth <me@sbooth.org>
 *  All Rights Reserved
 */

#import <Cocoa/Cocoa.h>

// ========================================
// NSOperation subclass providing a generic interface for submission to an online music database
// such as FreeDB or MusicBrainz
// ========================================
@interface MusicDatabaseSubmissionOperation : NSOperation
{
@protected
	NSData *_discTOC;					// Contains a CDTOC * as defined in <IOKit/storage/IOCDTypes.h>
	NSUInteger _freeDBDiscID;			// This disc's FreeDB disc ID
	NSString * _musicBrainzDiscID;		// This disc's MusicBrainz disc ID
	NSDictionary *_settings;			// A dictionary containing any settings configured by the user
	NSDictionary *_metadata;
	NSError *_error;
}

// ========================================
// Properties
@property (copy) NSData * discTOC;
@property (assign) NSUInteger freeDBDiscID;
@property (copy) NSString * musicBrainzDiscID;
@property (copy) NSDictionary * settings;
@property (copy) NSDictionary * metadata;
@property (readonly, copy) NSError * error;

@end
