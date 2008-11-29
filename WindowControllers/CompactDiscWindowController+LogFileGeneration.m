/*
 *  Copyright (C) 2008 Stephen F. Booth <me@sbooth.org>
 *  All Rights Reserved
 */

#import "CompactDiscWindowController+LogFileGeneration.h"

#import "ImageExtractionRecord.h"
#import "TrackExtractionRecord.h"

#import "DriveInformation.h"
#import "CompactDisc.h"
#import "AlbumMetadata.h"
#import "SessionDescriptor.h"
#import "TrackDescriptor.h"

#import "CDMSFFormatter.h"
#import "PregapFormatter.h"
#import "DurationFormatter.h"
#import "YesNoFormatter.h"

@interface CompactDiscWindowController (LogFileGenerationPrivate)
- (NSString *) headerSection;
- (NSString *) driveSection;
- (NSString *) discSection;
@end

@implementation CompactDiscWindowController (LogFileGeneration)

- (BOOL) writeLogFileToURL:(NSURL *)logFileURL forTrackExtractionRecords:(NSSet *)trackExtractionRecords error:(NSError **)error
{
	NSParameterAssert(nil != logFileURL);
	NSParameterAssert(nil != trackExtractionRecords);

	YesNoFormatter *yesNoFormatter = [[YesNoFormatter alloc] init];
	NSNumberFormatter *numberFormatter = [[NSNumberFormatter alloc] init];
	
	[numberFormatter setFormatterBehavior:NSNumberFormatterBehavior10_4];
	[numberFormatter setUsesGroupingSeparator:YES];
	
	NSMutableString *result = [NSMutableString string];
	
	[result appendString:[self headerSection]];
	[result appendString:@"\n"];
	
	[result appendString:[self driveSection]];
	[result appendString:@"\n"];
	
	[result appendString:[self discSection]];
	[result appendString:@"\n"];
	
	NSSortDescriptor *trackNumberSortDescriptor = [[NSSortDescriptor alloc] initWithKey:@"track.number" ascending:YES];
	NSArray *sortedExtractionRecords = [[trackExtractionRecords allObjects] sortedArrayUsingDescriptors:[NSArray arrayWithObject:trackNumberSortDescriptor]];
	
	[result appendString:@"Extracted Audio\n"];
	[result appendString:@"========================================\n"];
	
	for(TrackExtractionRecord *extractionRecord in sortedExtractionRecords) {		
		[result appendFormat:@"Track %@ saved to %@\n", extractionRecord.track.number, [[extractionRecord.outputURL path] lastPathComponent]];
		
		[result appendString:@"\n"];

		[result appendFormat:@"    Audio MD5 hash:         %@\n", extractionRecord.MD5];
		[result appendFormat:@"    Audio SHA1 hash:        %@\n", extractionRecord.SHA1];
		[result appendFormat:@"    AccurateRip checksum:   %08lx\n", extractionRecord.accurateRipChecksum.unsignedIntegerValue];

		if(extractionRecord.accurateRipConfidenceLevel) {
			[result appendString:@"\n"];
			
			[result appendFormat:@"    Accurately ripped:      %@\n", [yesNoFormatter stringForObjectValue:[NSNumber numberWithBool:YES]]];
			[result appendFormat:@"    Confidence level:       %@\n", [numberFormatter stringFromNumber:extractionRecord.accurateRipConfidenceLevel]];
			
			if(extractionRecord.accurateRipAlternatePressingChecksum) {
				[result appendFormat:@"    Alt. pressing offset:   %@\n", [numberFormatter stringFromNumber:extractionRecord.accurateRipAlternatePressingOffset]];
				[result appendFormat:@"    Alt. pressing checksum: %08lx\n", extractionRecord.accurateRipAlternatePressingChecksum.unsignedIntegerValue];
			}
		}		
		else if([extractionRecord.blockErrorFlags count]) {
			[result appendString:@"\n"];
			[result appendFormat:@"    C2 block error count:   %@\n", [numberFormatter stringForObjectValue:[NSNumber numberWithUnsignedInteger:[extractionRecord.blockErrorFlags count]]]];
			
//			NSIndexSet *onesIndexSet = [extractionRecord.errorFlags indexSetForOnes];
		}
		else {
			[result appendString:@"\n"];
			[result appendString:@"    Copy verified\n"];
		}
		
		[result appendString:@"\n"];
	}
	
	// If the file exists, append to it if desired
	if(0 && [[NSFileManager defaultManager] fileExistsAtPath:[logFileURL path]]) {
		// Read in the existing log file
		NSString *existingLogFile = [NSString stringWithContentsOfURL:logFileURL encoding:NSUTF8StringEncoding error:error];
		if(!existingLogFile)
			return NO;
		NSMutableString *appendedLogFile = [existingLogFile mutableCopy];
		[appendedLogFile appendString:@"\n\n"];
		[appendedLogFile appendString:result];
		
		return [appendedLogFile writeToURL:logFileURL atomically:YES encoding:NSUTF8StringEncoding error:error];
	}
	else
		return [result writeToURL:logFileURL atomically:YES encoding:NSUTF8StringEncoding error:error];
}

- (BOOL) writeLogFileToURL:(NSURL *)logFileURL forImageExtractionRecord:(ImageExtractionRecord *)imageExtractionRecord error:(NSError **)error
{
	NSParameterAssert(nil != logFileURL);
	NSParameterAssert(nil != imageExtractionRecord);
	
	YesNoFormatter *yesNoFormatter = [[YesNoFormatter alloc] init];
	NSNumberFormatter *numberFormatter = [[NSNumberFormatter alloc] init];
	
	[numberFormatter setFormatterBehavior:NSNumberFormatterBehavior10_4];
	[numberFormatter setUsesGroupingSeparator:YES];
	
	NSMutableString *result = [NSMutableString string];
	
	[result appendString:[self headerSection]];
	[result appendString:@"\n"];
	
	[result appendString:[self driveSection]];
	[result appendString:@"\n"];
	
	[result appendString:[self discSection]];
	[result appendString:@"\n"];
	
	[result appendString:@"Extracted Audio\n"];
	[result appendString:@"========================================\n"];
	
	[result appendFormat:@"Image saved to %@\n", [[imageExtractionRecord.outputURL path] lastPathComponent]];
	[result appendString:@"\n"];
	[result appendFormat:@"Audio MD5 hash:     %@\n", imageExtractionRecord.MD5];
	[result appendFormat:@"Audio SHA1 hash:    %@\n", imageExtractionRecord.SHA1];
	[result appendString:@"\n"];

	NSSortDescriptor *trackNumberSortDescriptor = [[NSSortDescriptor alloc] initWithKey:@"track.number" ascending:YES];
	NSArray *sortedExtractionRecords = [[imageExtractionRecord.tracks allObjects] sortedArrayUsingDescriptors:[NSArray arrayWithObject:trackNumberSortDescriptor]];
	
	for(TrackExtractionRecord *extractionRecord in sortedExtractionRecords) {				
		[result appendFormat:@"Track %@ \n", extractionRecord.track.number];
		
		[result appendString:@"\n"];
		
		[result appendFormat:@"    Audio MD5 hash:         %@\n", extractionRecord.MD5];
		[result appendFormat:@"    Audio SHA1 hash:        %@\n", extractionRecord.SHA1];
		[result appendFormat:@"    AccurateRip checksum:   %08lx\n", extractionRecord.accurateRipChecksum.unsignedIntegerValue];
		
		if(extractionRecord.accurateRipConfidenceLevel) {
			[result appendString:@"\n"];
			
			[result appendFormat:@"    Accurately ripped:      %@\n", [yesNoFormatter stringForObjectValue:[NSNumber numberWithBool:YES]]];
			[result appendFormat:@"    Confidence level:       %@\n", [numberFormatter stringFromNumber:extractionRecord.accurateRipConfidenceLevel]];
			
			if(extractionRecord.accurateRipAlternatePressingChecksum) {
				[result appendFormat:@"    Alt. pressing offset:   %@\n", [numberFormatter stringFromNumber:extractionRecord.accurateRipAlternatePressingOffset]];
				[result appendFormat:@"    Alt. pressing checksum: %08lx\n", extractionRecord.accurateRipAlternatePressingChecksum.unsignedIntegerValue];
			}
		}		
		else if([extractionRecord.blockErrorFlags count]) {
			[result appendString:@"\n"];
			[result appendFormat:@"    C2 block error count:   %@\n", [numberFormatter stringForObjectValue:[NSNumber numberWithUnsignedInteger:[extractionRecord.blockErrorFlags count]]]];
			
			//			NSIndexSet *onesIndexSet = [extractionRecord.errorFlags indexSetForOnes];
		}
		else {
			[result appendString:@"\n"];
			[result appendString:@"    Copy verified\n"];
		}
		
		[result appendString:@"\n"];
	}
	
	// If the file exists, append to it if desired
	if(0 && [[NSFileManager defaultManager] fileExistsAtPath:[logFileURL path]]) {
		// Read in the existing log file
		NSString *existingLogFile = [NSString stringWithContentsOfURL:logFileURL encoding:NSUTF8StringEncoding error:error];
		if(!existingLogFile)
			return NO;
		NSMutableString *appendedLogFile = [existingLogFile mutableCopy];
		[appendedLogFile appendString:@"\n\n"];
		[appendedLogFile appendString:result];
		
		return [appendedLogFile writeToURL:logFileURL atomically:YES encoding:NSUTF8StringEncoding error:error];
	}
	else
		return [result writeToURL:logFileURL atomically:YES encoding:NSUTF8StringEncoding error:error];
}

@end

@implementation CompactDiscWindowController (LogFileGenerationPrivate)

- (NSString *) headerSection
{
	NSDateFormatter *dateFormatter = [[NSDateFormatter alloc] init];
	
	[dateFormatter setFormatterBehavior:NSDateFormatterBehavior10_4];
	[dateFormatter setDateStyle:NSDateFormatterFullStyle];
	[dateFormatter setTimeStyle:NSDateFormatterFullStyle];
	
	NSString *appName = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleName"];
	NSString *shortVersionNumber = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleShortVersionString"];
	NSString *versionNumber = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleVersion"];
	
	NSMutableString *result = [NSMutableString string];
	
	[result appendFormat:@"%@ %@ (%@) Audio Extraction Log\n", appName, shortVersionNumber, versionNumber];
	[result appendString:@"========================================\n"];
	[result appendString:[dateFormatter stringFromDate:[NSDate date]]];
	[result appendString:@"\n"];
	
	return [result copy];
}

- (NSString *) driveSection
{
	YesNoFormatter *yesNoFormatter = [[YesNoFormatter alloc] init];
	NSNumberFormatter *numberFormatter = [[NSNumberFormatter alloc] init];
	
	[numberFormatter setFormatterBehavior:NSNumberFormatterBehavior10_4];
	[numberFormatter setUsesGroupingSeparator:YES];
	
	NSMutableString *result = [NSMutableString string];
	
	[result appendString:@"Drive Information\n"];
	[result appendString:@"========================================\n"];
	[result appendFormat:@"Drive used:         %@ %@", self.driveInformation.vendorName, self.driveInformation.productName];
	if(self.driveInformation.productRevisionLevel)
		[result appendFormat:@" (%@)", self.driveInformation.productRevisionLevel];
	[result appendString:@"\n"];
	if(self.driveInformation.productSerialNumber)
		[result appendFormat:@"Serial number:      %@\n", self.driveInformation.productSerialNumber];
	[result appendFormat:@"Interconnect type:  %@\n", self.driveInformation.physicalInterconnectType];
	[result appendFormat:@"Location:           %@\n", self.driveInformation.physicalInterconnectLocation];
	[result appendFormat:@"Stream accurate:    %@\n", [yesNoFormatter stringForObjectValue:self.driveInformation.hasAccurateStream]];
	[result appendFormat:@"Read offset:        %@\n", [numberFormatter stringFromNumber:self.driveInformation.readOffset]];
	
	return [result copy];
}

- (NSString *) discSection
{
	CDMSFFormatter *msfFormatter = [[CDMSFFormatter alloc] init];
	NSNumberFormatter *numberFormatter = [[NSNumberFormatter alloc] init];
	
	[numberFormatter setFormatterBehavior:NSNumberFormatterBehavior10_4];
	[numberFormatter setUsesGroupingSeparator:YES];
	[numberFormatter setPaddingCharacter:@" "];

	NSMutableString *result = [NSMutableString string];

	[result appendString:@"Compact Disc Information\n"];
	[result appendString:@"========================================\n"];
	[result appendString:@"Name:               "];
	if(self.compactDisc.metadata.artist)
		[result appendString:self.compactDisc.metadata.artist];
	else
		[result appendString:NSLocalizedString(@"Unknown Artist", @"")];
	[result appendString:NSLocalizedString(@" - ", @"Album - Artist separator")];
	if(self.compactDisc.metadata.title)
		[result appendString:self.compactDisc.metadata.title];
	else
		[result appendString:NSLocalizedString(@"Unknown Album", @"")];
	[result appendString:@"\n"];
	[result appendFormat:@"MusicBrainz ID:     %@\n", self.compactDisc.musicBrainzDiscID];
	[result appendFormat:@"FreeDB ID:          %08lx\n", self.compactDisc.freeDBDiscID];
	[result appendFormat:@"AccurateRip ID:     %.3d-%.8x-%.8x-%.8x\n", self.compactDisc.firstSession.tracks.count, self.compactDisc.accurateRipID1, self.compactDisc.accurateRipID2, self.compactDisc.freeDBDiscID];
	[result appendString:@"TOC:\n"];

	[result appendString:@"\n"];

	[result appendString:@" Track |   Start    |    Stop    |  Duration  |  First   |   Last   |  Total\n"];
	[result appendString:@"  Num  |  MM:SS.FF  |  MM:SS.FF  |  MM:SS.FF  |  Sector  |  Sector  | Sectors\n"];
	[result appendString:@"-------+------------+------------+------------+----------+----------+---------\n"];
	
	for(TrackDescriptor *trackDescriptor in self.compactDisc.firstSession.orderedTracks) {
		// Track number
		[result appendString:@"   "];
		[numberFormatter setFormatWidth:2];
		[result appendString:[numberFormatter stringFromNumber:trackDescriptor.number]];
		[result appendString:@"  |  "];
		
		// Start MM:SS.FF
		[result appendString:[msfFormatter stringForObjectValue:trackDescriptor.firstSector]];
		[result appendString:@"  |  "];
		
		// Stop MM:SS.FF
		[result appendString:[msfFormatter stringForObjectValue:trackDescriptor.lastSector]];
		[result appendString:@"  |  "];
		
		// Duration MM:SS.FF
		[result appendString:[msfFormatter stringForObjectValue:[NSNumber numberWithUnsignedInteger:(trackDescriptor.sectorCount - 150)]]];
		[result appendString:@"  |  "];
		
		// First sector
		[numberFormatter setFormatWidth:6];
		[result appendString:[numberFormatter stringFromNumber:trackDescriptor.firstSector]];
		[result appendString:@"  |  "];
		
		// Last sector
		[result appendString:[numberFormatter stringFromNumber:trackDescriptor.lastSector]];
		[result appendString:@"  |  "];
		
		// Total sectors
		[result appendString:[numberFormatter stringFromNumber:[NSNumber numberWithUnsignedInteger:trackDescriptor.sectorCount]]];
		[result appendString:@"\n"];
	}
	
//	[result appendString:@"+-------+------------+------------+------------+----------+----------+---------+\n"];

	return [result copy];
}

@end
