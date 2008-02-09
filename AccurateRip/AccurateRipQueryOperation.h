/*
 *  Copyright (C) 2008 Stephen F. Booth <me@sbooth.org>
 *  All Rights Reserved
 */

#import <Cocoa/Cocoa.h>

// ========================================
// An NSOperation subclass that queries the AccurateRip database for a 
// specific compact disc, and if found, creates the appropriate Core Data
// representation of the returned data
// ========================================
@interface AccurateRipQueryOperation : NSOperation
{
@private
	NSManagedObjectID *_compactDiscID;
	NSError *_error;
}

// ========================================
// Properties affecting the query
@property (assign) NSManagedObjectID * compactDiscID;

// ========================================
// Properties set after the query is complete (or cancelled)
@property (readonly, assign) NSError * error;

@end
