/*
 *  Copyright (C) 2009 Stephen F. Booth <me@sbooth.org>
 *  All Rights Reserved
 */

#import <Cocoa/Cocoa.h>

// ========================================
// NSString class extension
// ========================================
@interface NSString (PathSanitizationMethods)
- (NSString *) stringByRemovingIllegalPathCharacters;
- (NSString *) stringByReplacingIllegalPathCharactersWithString:(NSString *)string;

- (BOOL) hasDotPrefix;
- (NSString *) stringByRemovingDotPrefix;
- (NSString *) stringByRemovingPrefix:(NSString *)prefix;
@end

@interface NSMutableString (PathSanitizationMethods)
- (void) removeIllegalPathCharacters;
- (void) replaceIllegalPathCharactersWithString:(NSString *)string;

- (void) removeDotPrefix;
- (void) removePrefix:(NSString *)prefix;
@end
