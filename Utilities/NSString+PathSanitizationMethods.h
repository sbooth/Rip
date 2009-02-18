/*
 *  Copyright (C) 2009 Stephen F. Booth <me@sbooth.org>
 *  All Rights Reserved
 */

#import <Cocoa/Cocoa.h>

// ========================================
// NSString class extension
// ========================================
@interface NSString (PathSanitizationMethods)
- (NSString *) stripIllegalPathCharacters;
- (NSString *) replaceIllegalPathCharactersWithString:(NSString *)string;
@end
