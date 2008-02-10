/*
 *  Copyright (C) 2005 - 2007 Stephen F. Booth <me@sbooth.org>
 *  All Rights Reserved
 */

#import <Cocoa/Cocoa.h>

// ========================================
// A compact way of storing and accessing a array of YES/NO values
// ========================================
@interface BitArray : NSObject <NSCopying>
{
@private
	NSUInteger _bitCount;
	__strong NSUInteger *_bits;
}

@property (assign) NSUInteger bitCount;
@property (readonly) BOOL allZeroes;
@property (readonly) BOOL allOnes;
@property (readonly) NSUInteger countOfZeroes;
@property (readonly) NSUInteger countOfOnes;

- (id) initWithBitCount:(NSUInteger)bitCount;

// ========================================
// Access to the individual bits
- (BOOL) valueAtIndex:(NSUInteger)index;
- (void) setValue:(BOOL)value forIndex:(NSUInteger)index;

// ========================================
// Convenience methods
- (void) setAllZeroes;
- (void) setAllOnes;

@end
