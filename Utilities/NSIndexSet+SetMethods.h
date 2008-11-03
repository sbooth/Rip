/*
 *  Copyright (C) 2008 Stephen F. Booth <me@sbooth.org>
 *  All Rights Reserved
 */

#import <Cocoa/Cocoa.h>

// ========================================
// NSIndexSet class extension
// ========================================
@interface NSIndexSet (SetMethods)
- (BOOL) intersectsIndexSet:(NSIndexSet *)indexSet;
- (NSIndexSet *) intersectedIndexSet:(NSIndexSet *)indexSet;
@end

// ========================================
// NSMutableIndexSet class extension
// ========================================
@interface NSMutableIndexSet (SetMethods)
- (void) intersectIndexSet:(NSIndexSet *)indexSet;
@end
