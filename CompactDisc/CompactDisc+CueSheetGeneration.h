/*
 *  Copyright (C) 2008 - 2009 Stephen F. Booth <me@sbooth.org>
 *  All Rights Reserved
 */

#import <Cocoa/Cocoa.h>
#import "CompactDisc.h"

@interface CompactDisc (CueSheetGeneration)
- (NSString *) cueSheetString;
- (BOOL) writeCueSheetToURL:(NSURL *)cueSheetURL error:(NSError **)error;
@end
