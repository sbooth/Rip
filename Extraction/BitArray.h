/*
 *  Copyright (C) 2005 - 2009 Stephen F. Booth <me@sbooth.org>
 *  All Rights Reserved
 */

#import <Cocoa/Cocoa.h>

// ========================================
// A compact way of storing and accessing a array of YES/NO values
// ========================================
@interface BitArray : NSObject <NSCopying, NSCoding>
{
@private
	NSUInteger _bitCount;
	__strong NSUInteger *_bits;
}

// ========================================
// Properties
@property (assign) NSUInteger bitCount;
@property (readonly) BOOL allZeroes;
@property (readonly) BOOL allOnes;
@property (readonly) NSUInteger countOfZeroes;
@property (readonly) NSUInteger countOfOnes;
@property (readonly) NSIndexSet * indexSetForZeroes;
@property (readonly) NSIndexSet * indexSetForOnes;

// ========================================
// Creation
+ (id) bitArrayWithBitCount:(NSUInteger)bitCount;
- (id) initWithBitCount:(NSUInteger)bitCount;
- (id) initWithData:(NSData *)data;
- (id) initWithBits:(const void *)buffer bitCount:(NSUInteger)bitCount;

// ========================================
// Access to the individual bits
- (BOOL) valueAtIndex:(NSUInteger)index;
- (void) setValue:(BOOL)value forIndex:(NSUInteger)index;

// ========================================
// Convenience methods
- (void) setAllZeroes;
- (void) setAllOnes;

@end
