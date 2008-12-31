/*
 *  Copyright (C) 2008 Stephen F. Booth <me@sbooth.org>
 *  All Rights Reserved
 */

#import <Cocoa/Cocoa.h>

// ========================================
// NSImage class extension
// ========================================
@interface NSImage (BitmapRepresentationMethods)
- (NSData *) PNGData;
- (NSData *) bitmapDataForImageFileType:(NSBitmapImageFileType)imageFileType;
@end
