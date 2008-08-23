/*
 *  Copyright (C) 2008 Stephen F. Booth <me@sbooth.org>
 *  All Rights Reserved
 */

#import <Cocoa/Cocoa.h>
#import "MusicDatabaseInterface/MusicDatabaseQueryOperation.h"

// ========================================
// KVC key names for the properties dictionary
// ========================================
//extern NSString * const		kFLACCompressionLevelKey;	// NSNumber * (int)

// ========================================
// A MusicDatabaseQueryOperation subclass providing access to the MusicBrainz online database
// ========================================
@interface MusicBrainzQueryOperation : MusicDatabaseQueryOperation
{
}

@end
