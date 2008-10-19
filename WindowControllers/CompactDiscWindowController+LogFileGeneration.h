/*
 *  Copyright (C) 2008 Stephen F. Booth <me@sbooth.org>
 *  All Rights Reserved
 */

#import <Cocoa/Cocoa.h>
#import "CompactDiscWindowController.h"

@class ImageExtractionRecord;

@interface CompactDiscWindowController (LogFileGeneration)
- (BOOL) writeLogFileToURL:(NSURL *)logFileURL forTrackExtractionRecords:(NSArray *)trackExtractionRecords error:(NSError **)error;
- (BOOL) writeLogFileToURL:(NSURL *)logFileURL forImageExtractionRecord:(ImageExtractionRecord *)imageExtractionRecord error:(NSError **)error;
@end
