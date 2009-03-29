/*
 *  Copyright (C) 2008 Stephen F. Booth <me@sbooth.org>
 *  All Rights Reserved
 */

#import <Cocoa/Cocoa.h>

@class TrackDescriptor;

// ========================================
// This class encapsulates metadata pertaining to an entire album
// ========================================
@interface TrackMetadata : NSManagedObject
{
}

// ========================================
// Core Data properties
@property (assign) NSDictionary * additionalMetadata;
@property (assign) NSString * artist;
@property (assign) NSString * composer;
@property (assign) NSString * date;
@property (assign) NSString * genre;
@property (assign) NSString * ISRC;
@property (assign) NSString * lyrics;
@property (assign) NSString * musicBrainzID;
@property (assign) NSString * title;

// ========================================
// Core Data relationships
@property (assign) TrackDescriptor * track;

@end
