/*
 *  $Id$
 *  Copyright (C) 2005 - 2007 Stephen F. Booth <me@sbooth.org>
 *  All Rights Reserved
 */

#import "BitArray.h"

@interface BitArray (Private)
- (NSUInteger) arrayLength;
@end

@implementation BitArray

@synthesize bitCount = _bitCount;

- (id) copyWithZone:(NSZone *)zone
{
	BitArray *copy = [[[self class] allocWithZone:zone] init];
	
	copy.bitCount = self.bitCount;
	if(self.bitCount)
		memcpy(copy->_bits, _bits, self.arrayLength * sizeof(NSUInteger));
	
	return copy;
}

#pragma mark Bit Count

- (void) setBitCount:(NSUInteger)bitCount
{
	if(bitCount != self.bitCount) {
		_bitCount = bitCount;

		if(0 == bitCount)
			return;
		
		_bits = NSAllocateCollectable(self.arrayLength * sizeof(NSUInteger), 0);
		if(NULL == _bits) {
			NSLog(@"Unable to allocate memory");
			_bitCount = 0;
			return;
		}
		memset(_bits, 0, self.arrayLength * sizeof(NSUInteger));
	}
}

#pragma mark Bit Getting/Setting

- (BOOL) valueAtIndex:(NSUInteger)index
{
	NSParameterAssert(index < self.bitCount);
	
	NSUInteger arrayIndex = index / (8 * sizeof(NSUInteger));
	NSUInteger bitIndex = index % (8 * sizeof(NSUInteger));
	
	return (_bits[arrayIndex] & (1 << bitIndex) ? YES : NO);
}

- (void) setValue:(BOOL)value forIndex:(NSUInteger)index
{
	NSParameterAssert(index < self.bitCount);

	NSUInteger arrayIndex = index / (8 * sizeof(NSUInteger));
	NSUInteger bitIndex = index % (8 * sizeof(NSUInteger));
	uint32_t mask = value << bitIndex;
	
	if(value)
		_bits[arrayIndex] |= mask;
	else
		_bits[arrayIndex] &= mask;
}

#pragma mark Zero methods

- (BOOL) allZeroes
{
	NSUInteger lastArrayIndex = self.bitCount / (8 * sizeof(NSUInteger));
	NSUInteger lastBitIndex = self.bitCount % (8 * sizeof(NSUInteger));
	
	NSUInteger i;
	for(i = 0; i < lastArrayIndex; ++i) {
		if(0x00000000 != _bits[i])
			return NO;
	}
	
	for(i = 0; i < lastBitIndex; ++i) {
		if(0 != (_bits[lastArrayIndex] & (1 << i)))
			return NO;
	}
	
	return YES;
}

- (NSUInteger) countOfZeroes
{
	NSUInteger lastArrayIndex = self.bitCount / (8 * sizeof(NSUInteger));
	NSUInteger lastBitIndex = self.bitCount % (8 * sizeof(NSUInteger));
	NSUInteger result = 0;
	
	NSUInteger i, j;
	for(i = 0; i < lastArrayIndex; ++i) {
		if(!_bits[i]) {
			for(j = 0; j < (8 * sizeof(NSUInteger)); ++j) {
				if(!(_bits[i] & (1 << j)))
					++result;
			}
		}
	}
	
	for(i = 0; i < lastBitIndex; ++i) {
		if(!(_bits[lastArrayIndex] & (1 << i)))
			++result;
	}
	
	return result;
}

- (void) setAllZeroes
{
	NSUInteger lastArrayIndex = self.bitCount / (8 * sizeof(NSUInteger));
	NSUInteger lastBitIndex = self.bitCount % (8 * sizeof(NSUInteger));
	
	NSUInteger i;
	for(i = 0; i < lastArrayIndex; ++i)
		_bits[i] = 0x00000000;
	
	for(i = 0; i < lastBitIndex; ++i)
		_bits[lastArrayIndex] &= ~(1 << i);
}

#pragma mark One methods

- (BOOL) allOnes
{
	NSUInteger lastArrayIndex = self.bitCount / (8 * sizeof(NSUInteger));
	NSUInteger lastBitIndex = self.bitCount % (8 * sizeof(NSUInteger));
	
	NSUInteger i;
	for(i = 0; i < lastArrayIndex; ++i) {
		if(0xFFFFFFFF != _bits[i])
			return NO;
	}
	
	for(i = 0; i < lastBitIndex; ++i) {
		if(0 == (_bits[lastArrayIndex] & (1 << i)))
			return NO;
	}
	
	return YES;
}

- (NSUInteger) countOfOnes
{
	NSUInteger lastArrayIndex = self.bitCount / (8 * sizeof(NSUInteger));
	NSUInteger lastBitIndex = self.bitCount % (8 * sizeof(NSUInteger));
	NSUInteger result = 0;
	
	NSUInteger i, j;
	for(i = 0; i < lastArrayIndex; ++i) {
		if(_bits[i]) {
			for(j = 0; j < (8 * sizeof(NSUInteger)); ++j) {
				if(_bits[i] & (1 << j)) 
					++result;
			}
		}
	}
	
	for(i = 0; i < lastBitIndex; ++i) {
		if(_bits[lastArrayIndex] & (1 << i))
			++result;
	}
	
	return result;
}

- (void) setAllOnes
{	
	NSUInteger lastArrayIndex = self.bitCount / (8 * sizeof(NSUInteger));
	NSUInteger lastBitIndex = self.bitCount % (8 * sizeof(NSUInteger));

	NSUInteger i;
	for(i = 0; i < lastArrayIndex; ++i)
		_bits[i] = 0xFFFFFFFF;
	
	for(i = 0; i < lastBitIndex; ++i)
		_bits[lastArrayIndex] |= 1 << i;
}

- (NSString *) description
{
	NSMutableString *result = [NSMutableString string];

	NSUInteger i;
	for(i = 0; i < self.bitCount; ++i) {
		[result appendString:([self valueAtIndex:i] ? @"1" : @"0")];
		if(0 == i % 8)
			[result appendString:@" "];
		if(0 == i % 32)
			[result appendString:@"\n"];
	}
	
	return result;
}

@end

@implementation BitArray (Private)

- (NSUInteger) arrayLength
{
	return ((self.bitCount + ((8 * sizeof(NSUInteger)) - 1)) / (8 * sizeof(NSUInteger)));
}

@end
