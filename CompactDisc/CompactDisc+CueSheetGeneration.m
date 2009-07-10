/*
 *  Copyright (C) 2008 - 2009 Stephen F. Booth <me@sbooth.org>
 *  All Rights Reserved
 */

#import "CompactDisc+CueSheetGeneration.h"

#import "SessionDescriptor.h"
#import "TrackDescriptor.h"
#import "AlbumMetadata.h"
#import "TrackMetadata.h"

#import "ImageExtractionRecord.h"
#import "TrackExtractionRecord.h"

#import "CDDAUtilities.h"

@interface CompactDisc (CueSheetGenerationPrivate)
- (NSString *) cueSheetStringForImageExtractionRecord:(ImageExtractionRecord *)imageExtractionRecord orTrackExtractionRecords:(NSSet *)trackExtractionRecords;
@end

@implementation CompactDisc (CueSheetGeneration)

- (NSString *) cueSheetString
{
	return [self cueSheetStringForImageExtractionRecord:nil orTrackExtractionRecords:nil];
}

- (NSString *) cueSheetStringForImageExtractionRecord:(ImageExtractionRecord *)imageExtractionRecord
{
	NSParameterAssert(nil != imageExtractionRecord);
	
	return [self cueSheetStringForImageExtractionRecord:imageExtractionRecord orTrackExtractionRecords:nil];
}

- (NSString *) cueSheetStringForTrackExtractionRecords:(NSSet *)trackExtractionRecords
{
	NSParameterAssert(nil != trackExtractionRecords);
	NSParameterAssert([trackExtractionRecords count] == [self.firstSession.tracks count]);

	return [self cueSheetStringForImageExtractionRecord:nil orTrackExtractionRecords:trackExtractionRecords];
}

@end

@implementation CompactDisc (CueSheetGenerationPrivate)

- (NSString *) cueSheetStringForImageExtractionRecord:(ImageExtractionRecord *)imageExtractionRecord orTrackExtractionRecords:(NSSet *)trackExtractionRecords
{
	NSParameterAssert(!(imageExtractionRecord && trackExtractionRecords));
	
	NSMutableString *cueSheetString = [NSMutableString string];
	
	// For proper cue sheet generation, only strings with spaces are enclosed in quotes
	NSCharacterSet *whitespaceCharacterSet = [NSCharacterSet whitespaceCharacterSet];
	
	// Header
	NSString *appName = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleName"];
	NSString *shortVersionNumber = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleShortVersionString"];
	NSString *versionNumber = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleVersion"];	
	[cueSheetString appendFormat:@"REM Created by %@ %@ (%@)\n", appName, shortVersionNumber, versionNumber];
	
	[cueSheetString appendString:@"\n"];
	
	[cueSheetString appendFormat:@"REM FreeDB Disc ID %08x\n", self.freeDBDiscID];
	[cueSheetString appendFormat:@"REM MusicBrainz Disc ID %@\n", self.musicBrainzDiscID];
	
	NSString *date = self.metadata.date;
	if(date && [date length]) {
		NSRange whitespaceRange = [date rangeOfCharacterFromSet:whitespaceCharacterSet];
		if(NSNotFound == whitespaceRange.location && 0 == whitespaceRange.length)
			[cueSheetString appendFormat:@"REM DATE %@\n", date];
		else
			[cueSheetString appendFormat:@"REM DATE \"%@\"\n", date];
	}
	
	[cueSheetString appendString:@"\n"];
	
	NSString *MCN = self.metadata.MCN;
	if(MCN && [MCN length] && [MCN integerValue])
		[cueSheetString appendFormat:@"CATALOG %@\n", self.metadata.MCN];
	
	// Title, artist
	NSString *title = self.metadata.title;
	if(title && [title length]) {
		NSRange whitespaceRange = [title rangeOfCharacterFromSet:whitespaceCharacterSet];
		if(NSNotFound == whitespaceRange.location && 0 == whitespaceRange.length)
			[cueSheetString appendFormat:@"TITLE %@\n", title];
		else
			[cueSheetString appendFormat:@"TITLE \"%@\"\n", title];
	}
	
	NSString *artist = self.metadata.artist;
	if(artist && [artist length]) {
		NSRange whitespaceRange = [artist rangeOfCharacterFromSet:whitespaceCharacterSet];
		if(NSNotFound == whitespaceRange.location && 0 == whitespaceRange.length)
			[cueSheetString appendFormat:@"PERFORMER %@\n", artist];
		else
			[cueSheetString appendFormat:@"PERFORMER \"%@\"\n", artist];
	}
	
	if(imageExtractionRecord)
		[cueSheetString appendFormat:@"FILE \"%@\" WAVE\n", [[imageExtractionRecord.outputURL path] lastPathComponent]];		
	
	[cueSheetString appendString:@"\n"];
	
	for(TrackDescriptor *trackDescriptor in self.firstSession.orderedTracks) {
		// Track number
		[cueSheetString appendFormat:@"TRACK %02i AUDIO\n", trackDescriptor.number.integerValue];

		if(trackExtractionRecords) {
			for(TrackExtractionRecord *trackExtractionRecord in trackExtractionRecords) {
				if([trackExtractionRecord.track.number isEqualToNumber:trackDescriptor.number])
					[cueSheetString appendFormat:@"  FILE \"%@\" WAVE\n", [[trackExtractionRecord.outputURL path] lastPathComponent]];
			}
		}
				
		// ISRC
		if(trackDescriptor.metadata.ISRC)
			[cueSheetString appendFormat:@"  ISRC %@\n", trackDescriptor.metadata.ISRC];
		
		CDMSF trackMSF = CDConvertLBAToMSF(trackDescriptor.firstSector.integerValue - 150);
		
		// Pregap (track 1 always has a pregap of at least 2 sec)
		if(trackDescriptor.pregap && trackDescriptor.pregap.integerValue) {
			// INDEX 00 uses audio from the file to fill the pregap
			if(1 != trackDescriptor.number.unsignedIntegerValue || (1 == trackDescriptor.number.unsignedIntegerValue && 150 != trackDescriptor.pregap.integerValue)) {
				CDMSF trackPregapMSF = CDConvertLBAToMSF(trackDescriptor.pregap.integerValue - 150);
				CDMSF trackRelativePregapMSF = subtractCDMSF(trackMSF, trackPregapMSF);
				[cueSheetString appendFormat:@"  INDEX 00 %02i:%02i:%02i\n", trackRelativePregapMSF.minute, trackRelativePregapMSF.second, trackRelativePregapMSF.frame];
			}
			// PREGAP indicates digital silence to be generated by the burner
			else {
				CDMSF trackPregapMSF = CDConvertLBAToMSF(trackDescriptor.pregap.integerValue - 150);
				[cueSheetString appendFormat:@"  PREGAP %02i:%02i:%02i\n", trackPregapMSF.minute, trackPregapMSF.second, trackPregapMSF.frame];
			}
		}
		
		// Index
		[cueSheetString appendFormat:@"  INDEX 01 %02i:%02i:%02i\n", trackMSF.minute, trackMSF.second, trackMSF.frame];
		
		// Flags
		NSMutableArray *flagsArray = [NSMutableArray array];
		if(trackDescriptor.digitalCopyPermitted.boolValue)
			[flagsArray addObject:@"DCP"];
		if(trackDescriptor.hasPreEmphasis.boolValue)
			[flagsArray addObject:@"PRE"];
		if(4 == trackDescriptor.channelsPerFrame.integerValue)
			[flagsArray addObject:@"4CH"];
		if(trackDescriptor.isDataTrack.boolValue)
			[flagsArray addObject:@"DATA"];
		
		if(flagsArray.count)
			[cueSheetString appendFormat:@"  FLAGS %@\n", [flagsArray componentsJoinedByString:@" "]];
		
		// Track title, artist and composer
		title = trackDescriptor.metadata.title;
		if(title && [title length]) {
			NSRange whitespaceRange = [title rangeOfCharacterFromSet:whitespaceCharacterSet];
			if(NSNotFound == whitespaceRange.location && 0 == whitespaceRange.length)
				[cueSheetString appendFormat:@"  TITLE %@\n", title];
			else
				[cueSheetString appendFormat:@"  TITLE \"%@\"\n", title];
		}
		
		artist = trackDescriptor.metadata.artist;
		if(artist && [artist length]) {
			NSRange whitespaceRange = [artist rangeOfCharacterFromSet:whitespaceCharacterSet];
			if(NSNotFound == whitespaceRange.location && 0 == whitespaceRange.length)
				[cueSheetString appendFormat:@"  PERFORMER %@\n", artist];
			else
				[cueSheetString appendFormat:@"  PERFORMER \"%@\"\n", artist];
		}
		
		NSString *composer = trackDescriptor.metadata.composer;
		if(composer && [composer length]) {
			NSRange whitespaceRange = [composer rangeOfCharacterFromSet:whitespaceCharacterSet];
			if(NSNotFound == whitespaceRange.location && 0 == whitespaceRange.length)
				[cueSheetString appendFormat:@"  SONGWRITER %@\n", composer];
			else
				[cueSheetString appendFormat:@"  SONGWRITER \"%@\"\n", composer];
		}
		
		[cueSheetString appendString:@"\n"];
	}
	
	return [cueSheetString copy];
}

@end
