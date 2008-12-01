/*
 *  Copyright (C) 2008 Stephen F. Booth <me@sbooth.org>
 *  All Rights Reserved
 */

#import "CDDAUtilitiesTest.h"

#import "CDDAUtilities.h"

@implementation CDDAUtilitiesTest

- (void) testAddCDMSF
{
	CDMSF a = {2, 40, 65};
	CDMSF b = {2, 37, 20};

	CDMSF sum = {5, 18, 10};
	CDMSF result = addCDMSF(a, b);
	
	STAssertEquals(sum, result, @"addCDMSF");
}

- (void) testSubtractCDMSF
{
	CDMSF a = {2, 40, 65};
	CDMSF b = {2, 37, 20};
	
	CDMSF difference = {0, 3, 45};
	CDMSF result = subtractCDMSF(a, b);
	
	STAssertEquals(difference, result, @"subtractCDMSF");
}

@end
