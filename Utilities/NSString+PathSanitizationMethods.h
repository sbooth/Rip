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
@end

@interface NSMutableString (PathSanitizationMethods)
- (void) removeIllegalPathCharacters;
- (void) replaceIllegalPathCharactersWithString:(NSString *)string;
@end
