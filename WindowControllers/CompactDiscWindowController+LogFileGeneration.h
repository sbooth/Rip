/*
 *  Copyright (C) 2008 Stephen F. Booth <me@sbooth.org>
 *  All Rights Reserved
 */

#import <Cocoa/Cocoa.h>
#import "CompactDiscWindowController.h"

@class ImageExtractionRecord;

@interface CompactDiscWindowController (LogFileGeneration)
- (BOOL) writeLogFileToURL:(NSURL *)logFileURL trackExtractionRecords:(NSSet *)trackExtractionRecords error:(NSError **)error;
- (BOOL) writeLogFileToURL:(NSURL *)logFileURL imageExtractionRecord:(ImageExtractionRecord *)imageExtractionRecord error:(NSError **)error;
@end
