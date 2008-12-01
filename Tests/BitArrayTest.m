/*
 *  Copyright (C) 2008 Stephen F. Booth <me@sbooth.org>
 *  All Rights Reserved
 */

#import "BitArrayTest.h"

#import "BitArray.h"

@implementation BitArrayTest

- (void) testBitArrayCapacity
{
	BitArray *ba = [[BitArray alloc] initWithBitCount:10];
	STAssertNoThrow([ba setValue:YES forIndex:9], @"BitArray should handle indexes <= bitcount");
	STAssertThrows([ba setValue:YES forIndex:10], @"BitArray should throw if index >= bitcount");
}

@end
