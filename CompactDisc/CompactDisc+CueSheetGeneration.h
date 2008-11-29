/*
 *  Copyright (C) 2008 Stephen F. Booth <me@sbooth.org>
 *  All Rights Reserved
 */

#import <Cocoa/Cocoa.h>
#import "CompactDisc.h"

@interface CompactDisc (CueSheetGeneration)
- (BOOL) writeCueSheetToURL:(NSURL *)cueSheetURL error:(NSError **)error;
@end
