/*
 *  Copyright (C) 2009 Stephen F. Booth <me@sbooth.org>
 *  All Rights Reserved
 */

#import "MusicDatabaseSubmissionOperation.h"

@interface MusicDatabaseSubmissionOperation ()
@property (copy) NSError * error;
@end

@implementation MusicDatabaseSubmissionOperation

// ========================================
// Properties
@synthesize discTOC = _discTOC;
@synthesize freeDBDiscID = _freeDBDiscID;
@synthesize musicBrainzDiscID = _musicBrainzDiscID;
@synthesize settings = _settings;
@synthesize metadata = _metadata;
@synthesize error = _error;

@end
