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

#import "BitArray.h"

@interface CompactDiscWindowController (LogFileGenerationPrivate)
- (NSString *) headerSection;
- (NSString *) driveSection;
- (NSString *) discSection;
@end

@implementation CompactDiscWindowController (LogFileGeneration)

- (BOOL) writeLogFileToURL:(NSURL *)logFileURL forTrackExtractionRecords:(NSArray *)trackExtractionRecords error:(NSError **)error
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
	NSArray *sortedExtractionRecords = [trackExtractionRecords sortedArrayUsingDescriptors:[NSArray arrayWithObject:trackNumberSortDescriptor]];
	
	for(TrackExtractionRecord *extractionRecord in sortedExtractionRecords) {		
		[result appendFormat:@"Track %@ saved to %@\n", extractionRecord.track.number, [[extractionRecord.URL path] lastPathComponent]];
		
		[result appendFormat:@"    Audio MD5 hash:         %@\n", extractionRecord.MD5];
		[result appendFormat:@"    Audio SHA1 hash:        %@\n", extractionRecord.SHA1];
		if([extractionRecord.errorFlags countOfOnes]) {
			[result appendFormat:@"    C2 error count:         %@\n", [numberFormatter stringForObjectValue:[NSNumber numberWithUnsignedInteger:[extractionRecord.errorFlags countOfOnes]]]];
			
//			NSIndexSet *onesIndexSet = [extractionRecord.errorFlags indexSetForOnes];
		}
		[result appendFormat:@"    AccurateRip checksum:   %08lx\n", extractionRecord.accurateRipChecksum.unsignedIntegerValue];
		
		if(extractionRecord.accurateRipConfidenceLevel) {
			[result appendFormat:@"    Accurately ripped:      %@\n", [yesNoFormatter stringForObjectValue:[NSNumber numberWithBool:YES]]];
			[result appendFormat:@"    Confidence level:       %@\n", [numberFormatter stringFromNumber:extractionRecord.accurateRipConfidenceLevel]];
		}
		
		[result appendString:@"\n"];
	}
	
	return [result writeToURL:logFileURL atomically:YES encoding:NSUTF8StringEncoding error:error];
}

- (BOOL) writeLogFileToURL:(NSURL *)logFileURL forImageExtractionRecord:(ImageExtractionRecord *)imageExtractionRecord error:(NSError **)error
{
	NSParameterAssert(nil != logFileURL);
	NSParameterAssert(nil != imageExtractionRecord);
	
	NSMutableString *result = [NSMutableString string];
	
	[result appendString:[self headerSection]];
	[result appendString:@"\n"];
	
	[result appendString:[self driveSection]];
	[result appendString:@"\n"];
	
	[result appendString:[self discSection]];
	[result appendString:@"\n"];
	
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

	[result appendString:@"Disc name:          "];
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
	[result appendFormat:@"FreeDB ID:          %08lx\n", self.compactDisc.freeDBDiscID.integerValue];
	[result appendFormat:@"MusicBrainz ID:     %@\n", self.compactDisc.musicBrainzDiscID];
	[result appendString:@"Disc TOC:\n"];
	
	[result appendString:@"+-------+------------+------------+------------+----------+----------+---------+\n"];
	[result appendString:@"| Track |   Start    |    Stop    |  Duration  |  First   |   Last   |  Total  |\n"];
	[result appendString:@"|  Num. |  MM:SS.FF  |  MM:SS.FF  |  MM:SS.FF  |  Sector  |  Sector  | Sectors |\n"];
	[result appendString:@"+-------+------------+------------+------------+----------+----------+---------+\n"];
	
	for(TrackDescriptor *trackDescriptor in self.compactDisc.firstSession.orderedTracks) {
		// Track number
		[result appendString:@"|   "];
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
		[result appendString:@" |\n"];
	}
	
	[result appendString:@"+-------+------------+------------+------------+----------+----------+---------+\n"];

	return [result copy];
}

@end
