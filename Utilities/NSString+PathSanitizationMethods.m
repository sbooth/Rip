/*
 *  Copyright (C) 2009 Stephen F. Booth <me@sbooth.org>
 *  All Rights Reserved
 */

#import "NSString+PathSanitizationMethods.h"

@implementation NSString (PathSanitizationMethods)

- (NSString *) stripIllegalPathCharacters
{
	return [self replaceIllegalPathCharactersWithString:@""];
}

- (NSString *) replaceIllegalPathCharactersWithString:(NSString *)string
{
	NSParameterAssert(nil != string);

	// The following character set contains the characters that should not appear in pathnames or filenames
	NSCharacterSet *illegalFilenameCharacters = [NSCharacterSet characterSetWithCharactersInString:@"\"\\/<>?:*|"];
	NSMutableString *result = [self mutableCopy];
	
	NSRange range = [result rangeOfCharacterFromSet:illegalFilenameCharacters];		
	while(NSNotFound != range.location && 0 != range.length) {
		[result replaceCharactersInRange:range withString:string];
		range = [result rangeOfCharacterFromSet:illegalFilenameCharacters];		
	}
	
	return [result copy];
}

@end
