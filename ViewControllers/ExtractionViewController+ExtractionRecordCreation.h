/*
 *  Copyright (C) 2008 - 2009 Stephen F. Booth <me@sbooth.org>
 *  All Rights Reserved
 */

#import <Cocoa/Cocoa.h>
#import "ExtractionViewController.h"

@class ExtractionOperation, TrackDescriptor, TrackExtractionRecord, ImageExtractionRecord;

// ========================================
// Methods for creating track and image extraction records
// ========================================
@interface ExtractionViewController (ExtractionRecordCreation)
- (NSURL *) prependAndAppendSilenceForTrackURL:(NSURL *)fileURL error:(NSError **)error;
- (NSURL *) generateOutputFileForURL:(NSURL *)inputURL containsSilence:(BOOL)containsSilence error:(NSError **)error;

- (TrackExtractionRecord *) createTrackExtractionRecordForFileURL:(NSURL *)fileURL;
- (TrackExtractionRecord *) createTrackExtractionRecordForFileURL:(NSURL *)fileURL accurateRipChecksum:(NSUInteger)accurateRipChecksum accurateRipConfidenceLevel:(NSNumber *)accurateRipConfidenceLevel;

- (TrackExtractionRecord *) createTrackExtractionRecordForFileURL:(NSURL *)fileURL accurateRipChecksum:(NSUInteger)accurateRipChecksum accurateRipConfidenceLevel:(NSNumber *)accurateRipConfidenceLevel accurateRipAlternatePressingChecksum:(NSUInteger)accurateRipAlternatePressingChecksum accurateRipAlternatePressingOffset:(NSNumber *)accurateRipAlternatePressingOffset;

- (TrackExtractionRecord *) createTrackExtractionRecordForFileURL:(NSURL *)fileURL blockErrorFlags:(NSIndexSet *)blockErrorFlags accurateRipChecksum:(NSUInteger)accurateRipChecksum accurateRipConfidenceLevel:(NSNumber *)accurateRipConfidenceLevel accurateRipAlternatePressingChecksum:(NSUInteger)accurateRipAlternatePressingChecksum accurateRipAlternatePressingOffset:(NSNumber *)accurateRipAlternatePressingOffset;

- (void) addTrackExtractionRecord:(TrackExtractionRecord *)extractionRecord;

- (ImageExtractionRecord *) createImageExtractionRecord;

@end

