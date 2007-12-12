/*
 *  Copyright (C) 2007 Stephen F. Booth <me@sbooth.org>
 *  All Rights Reserved
 */

#import <Cocoa/Cocoa.h>

@class CompactDisc, AccurateRipTrack;

// ========================================
// Class providing access to information in the AccurateRip database
// for the given CompactDisc
// ========================================
@interface AccurateRipDisc : NSObject <NSCopying>
{
	CompactDisc *_compactDisc;
	NSMutableArray *_tracks;
	
	NSUInteger _accurateRipID1;
	NSUInteger _accurateRipID2;
	
	NSURLConnection *_connection;
	NSMutableData *_responseData;
	NSError *_error;
	
	BOOL _discFound;
}

@property (readonly, assign) CompactDisc * compactDisc;
@property (readonly, assign) BOOL discFound;
@property (readonly, copy) NSError * error;
@property (readonly, assign) NSUInteger accurateRipID1;
@property (readonly, assign) NSUInteger accurateRipID2;
@property (readonly) NSArray * tracks;

- (id) initWithCompactDisc:(CompactDisc *)compactDisc;

- (IBAction) performAccurateRipQuery:(id)sender;

- (AccurateRipTrack *) trackNumber:(NSUInteger)trackNumber;

@end
