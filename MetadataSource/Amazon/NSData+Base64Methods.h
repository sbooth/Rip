/*
 *  Copyright (C) 2009 Stephen F. Booth <me@sbooth.org>
 *  All Rights Reserved
 */

#import <Cocoa/Cocoa.h>

@interface NSData (Base64Methods)
- (NSString *) base64EncodedString;
- (NSString *) base64EncodedStringWithNewlines:(BOOL)encodeWithNewlines;
@end
