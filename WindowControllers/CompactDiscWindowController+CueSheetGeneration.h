/*
 *  Copyright (C) 2008 Stephen F. Booth <me@sbooth.org>
 *  All Rights Reserved
 */

#import <Cocoa/Cocoa.h>
#import "CompactDiscWindowController.h"

@interface CompactDiscWindowController (CueSheetGeneration)
- (BOOL) writeCueSheetToURL:(NSURL *)cueSheetURL error:(NSError **)error;
@end
