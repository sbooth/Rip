/*
 *  Copyright (C) 2008 - 2009 Stephen F. Booth <me@sbooth.org>
 *  All Rights Reserved
 */

#import <Cocoa/Cocoa.h>
#import "CompactDisc.h"

@class ImageExtractionRecord;

@interface CompactDisc (CueSheetGeneration)
- (NSString *) cueSheetString;
- (NSString *) cueSheetStringForImageExtractionRecord:(ImageExtractionRecord *)imageExtractionRecord;
- (NSString *) cueSheetStringForTrackExtractionRecords:(NSSet *)trackExtractionRecords;
@end
