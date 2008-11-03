/*
 *  Copyright (C) 2008 Stephen F. Booth <me@sbooth.org>
 *  All Rights Reserved
 */

#import "NSIndexSet+SetMethods.h"

@implementation NSIndexSet (SetMethods)

- (BOOL) intersectsIndexSet:(NSIndexSet *)indexSet
{
	NSParameterAssert(nil != indexSet);

	NSUInteger currentIndex = [indexSet firstIndex];
	while(NSNotFound != currentIndex) {
		
		if([self containsIndex:currentIndex])
			return YES;
		
		currentIndex = [indexSet indexGreaterThanIndex:currentIndex];
	}
	
	return NO;
}

- (NSIndexSet *) intersectedIndexSet:(NSIndexSet *)indexSet
{
	NSParameterAssert(nil != indexSet);
	
	NSMutableIndexSet *intersectedSet = [NSMutableIndexSet indexSet];
	
	NSUInteger currentIndex = [indexSet firstIndex];
	while(NSNotFound != currentIndex) {
		
		if([self containsIndex:currentIndex])
			[intersectedSet addIndex:currentIndex];
		
		currentIndex = [indexSet indexGreaterThanIndex:currentIndex];
	}

	return [intersectedSet copy];
}

@end

@implementation NSMutableIndexSet (SetMethods)

// Intersects the given NSIndexSet with self
- (void) intersectIndexSet:(NSIndexSet *)indexSet
{
	NSParameterAssert(nil != indexSet);
	
	NSIndexSet *selfCopy = [self copy];
	
	[self removeAllIndexes];
	
	NSUInteger currentIndex = [indexSet firstIndex];
	while(NSNotFound != currentIndex) {
		
		if([selfCopy containsIndex:currentIndex])
			[self addIndex:currentIndex];
		
		currentIndex = [indexSet indexGreaterThanIndex:currentIndex];
	}
}

@end
