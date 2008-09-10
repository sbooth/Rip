/*
 *  Copyright (C) 2008 Stephen F. Booth <me@sbooth.org>
 *  All Rights Reserved
 */

#import <Cocoa/Cocoa.h>

@interface ReadOffsetVerificationOperation : NSOperation
{
@private
	NSURL *_URL;
	NSManagedObjectID *_trackDescriptorID;
	NSNumber *_trackFirstSectorOffset;
	NSNumber *_offsetToVerify;
	NSError *_error;
	NSNumber *_offsetVerified;
}

// ========================================
// Properties affecting scanning
@property (assign) NSURL * URL;
@property (assign) NSManagedObjectID * trackDescriptorID; // Should NOT be the first or last track on the disc
@property (assign) NSNumber * trackFirstSectorOffset; // In URL
@property (assign) NSNumber * offsetToVerify; // In sample frames

// ========================================
// Properties set after offset verification is complete (or cancelled)
@property (readonly, assign) NSError * error;
@property (readonly, assign) NSNumber * offsetVerified;

@end
