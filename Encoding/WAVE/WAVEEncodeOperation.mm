/*
 *  Copyright (C) 2008 - 2009 Stephen F. Booth <me@sbooth.org>
 *  All Rights Reserved
 */

#import "WAVEEncodeOperation.h"
#import "NSImage+BitmapRepresentationMethods.h"

#include <taglib/wavfile.h>
#include <taglib/textidentificationframe.h>
#include <taglib/unsynchronizedlyricsframe.h>
#include <taglib/uniquefileidentifierframe.h>
#include <taglib/attachedpictureframe.h>
#include <taglib/relativevolumeframe.h>

// ========================================
// Utility function to get a timestamp in the format required by ID3v2 tags
// ========================================
static NSString *
getID3v2Timestamp()
{
	[NSDateFormatter setDefaultFormatterBehavior:NSDateFormatterBehavior10_4];

	NSDateFormatter *dateFormatter = [[NSDateFormatter alloc] init];

	[dateFormatter setTimeZone:[NSTimeZone timeZoneWithAbbreviation:@"GMT"]];
	[dateFormatter setDateFormat:@"yyyy'-'MM'-'dd'T'HH':'mm':'ss"];

	return [dateFormatter stringFromDate:[NSDate date]];
}

@implementation WAVEEncodeOperation

// ========================================
// The amount of time to sleep while waiting for the NSTask to finish
// ========================================
#define SLEEP_TIME_INTERVAL ((NSTimeInterval)0.25)

- (void) main
{	
	// The superclass takes care of the encoding
	[super main];
		
	// Stop now if the operation was cancelled or any errors occurred
	if(self.isCancelled || self.error)
		return;
	
	// ========================================
	// TAGGING

	TagLib::ID3v2::TextIdentificationFrame *textFrame = NULL;
	
	// Open the file to tag
	TagLib::RIFF::WAV::File fileRef([[self.outputURL path] fileSystemRepresentation], false);

	if(!fileRef.isValid()) {
		self.error = [NSError errorWithDomain:NSPOSIXErrorDomain code:EIO userInfo:nil];
		return;
	}
	
	// Use UTF-8 as the default encoding
	(TagLib::ID3v2::FrameFactory::instance())->setDefaultTextEncoding(TagLib::String::UTF8);

	// Title
	if([self.metadata objectForKey:kMetadataTitleKey])
		fileRef.tag()->setTitle(TagLib::String([[self.metadata objectForKey:kMetadataTitleKey] UTF8String], TagLib::String::UTF8));

	// Album title
	if([self.metadata objectForKey:kMetadataAlbumTitleKey])
		fileRef.tag()->setAlbum(TagLib::String([[self.metadata objectForKey:kMetadataAlbumTitleKey] UTF8String], TagLib::String::UTF8));
	
	// Artist
	if([self.metadata objectForKey:kMetadataArtistKey])
		fileRef.tag()->setArtist(TagLib::String([[self.metadata objectForKey:kMetadataArtistKey] UTF8String], TagLib::String::UTF8));

	// Album artist
	if([self.metadata objectForKey:kMetadataAlbumArtistKey]) {
		textFrame = new TagLib::ID3v2::TextIdentificationFrame("TPE2", TagLib::String::Latin1);
		if(!textFrame) {
			self.error = [NSError errorWithDomain:NSPOSIXErrorDomain code:ENOMEM userInfo:nil];
			return;
		}
		
		textFrame->setText(TagLib::String([[self.metadata objectForKey:kMetadataAlbumArtistKey] UTF8String], TagLib::String::UTF8));
		fileRef.tag()->addFrame(textFrame);
	}
	
	// Genre
	if([self.metadata objectForKey:kMetadataGenreKey])
		fileRef.tag()->setGenre(TagLib::String([[self.metadata objectForKey:kMetadataGenreKey] UTF8String], TagLib::String::UTF8));

	// Composer
	if([self.metadata objectForKey:kMetadataComposerKey]) {
		textFrame = new TagLib::ID3v2::TextIdentificationFrame("TCOM", TagLib::String::Latin1);
		if(!textFrame) {
			self.error = [NSError errorWithDomain:NSPOSIXErrorDomain code:ENOMEM userInfo:nil];
			return;
		}
		
		textFrame->setText(TagLib::String([[self.metadata objectForKey:kMetadataComposerKey] UTF8String], TagLib::String::UTF8));
		fileRef.tag()->addFrame(textFrame);
	}

	// Release date
	if([self.metadata objectForKey:kMetadataReleaseDateKey]) {
		// Attempt to parse the release date
		NSDate *releaseDate = [NSDate dateWithNaturalLanguageString:[self.metadata objectForKey:kMetadataReleaseDateKey]];
		if(releaseDate) {
			NSCalendar *gregorianCalendar = [[NSCalendar alloc] initWithCalendarIdentifier:NSGregorianCalendar];
			NSDateComponents *releaseDateComponents = [gregorianCalendar components:NSYearCalendarUnit fromDate:releaseDate];
			fileRef.tag()->setYear((TagLib::uint)[releaseDateComponents year]);
		}		
	}
	
	// Compilation
	if([[self.metadata objectForKey:kMetadataCompilationKey] boolValue]) {
		textFrame = new TagLib::ID3v2::TextIdentificationFrame("TCMP", TagLib::String::Latin1);
		if(!textFrame) {
			self.error = [NSError errorWithDomain:NSPOSIXErrorDomain code:ENOMEM userInfo:nil];
			return;
		}
		
		textFrame->setText(TagLib::String([@"1" UTF8String], TagLib::String::UTF8));
		fileRef.tag()->addFrame(textFrame);
	}
	
	// Track number and total
	NSNumber *trackNumber = [self.metadata objectForKey:kMetadataTrackNumberKey];
	NSNumber *trackTotal = [self.metadata objectForKey:kMetadataTrackTotalKey];
	if(trackNumber && trackTotal) {
		textFrame = new TagLib::ID3v2::TextIdentificationFrame("TRCK", TagLib::String::Latin1);
		if(!textFrame) {
			self.error = [NSError errorWithDomain:NSPOSIXErrorDomain code:ENOMEM userInfo:nil];
			return;
		}
		
		textFrame->setText(TagLib::String([[NSString stringWithFormat:@"%u/%u", [trackNumber intValue], [trackTotal intValue]] UTF8String], TagLib::String::UTF8));
		fileRef.tag()->addFrame(textFrame);
	}
	else if(trackNumber)
		fileRef.tag()->setTrack([trackNumber intValue]);
	else if(trackTotal) {
		textFrame = new TagLib::ID3v2::TextIdentificationFrame("TRCK", TagLib::String::Latin1);
		if(!textFrame) {
			self.error = [NSError errorWithDomain:NSPOSIXErrorDomain code:ENOMEM userInfo:nil];
			return;
		}
		
		textFrame->setText(TagLib::String([[NSString stringWithFormat:@"/%u", [trackTotal intValue]] UTF8String], TagLib::String::UTF8));
		fileRef.tag()->addFrame(textFrame);
	}

	// Disc number and total
	NSNumber *discNumber = [self.metadata objectForKey:kMetadataDiscNumberKey];
	NSNumber *discTotal = [self.metadata objectForKey:kMetadataDiscTotalKey];
	if(discNumber && discTotal) {
		textFrame = new TagLib::ID3v2::TextIdentificationFrame("TPOS", TagLib::String::Latin1);
		if(!textFrame) {
			self.error = [NSError errorWithDomain:NSPOSIXErrorDomain code:ENOMEM userInfo:nil];
			return;
		}
		
		textFrame->setText(TagLib::String([[NSString stringWithFormat:@"%u/%u", [discNumber intValue], [discTotal intValue]] UTF8String], TagLib::String::UTF8));
		fileRef.tag()->addFrame(textFrame);
	}
	else if(discNumber)
		fileRef.tag()->setTrack([discNumber intValue]);
	else if(discTotal) {
		textFrame = new TagLib::ID3v2::TextIdentificationFrame("TPOS", TagLib::String::Latin1);
		if(!textFrame) {
			self.error = [NSError errorWithDomain:NSPOSIXErrorDomain code:ENOMEM userInfo:nil];
			return;
		}
		
		textFrame->setText(TagLib::String([[NSString stringWithFormat:@"/%u", [discTotal intValue]] UTF8String], TagLib::String::UTF8));
		fileRef.tag()->addFrame(textFrame);
	}
	
	// Lyrics
	if([self.metadata objectForKey:kMetadataLyricsKey]) {
		TagLib::ID3v2::UnsynchronizedLyricsFrame *lyricsFrame = new TagLib::ID3v2::UnsynchronizedLyricsFrame(TagLib::String::UTF8);
		if(!lyricsFrame) {
			self.error = [NSError errorWithDomain:NSPOSIXErrorDomain code:ENOMEM userInfo:nil];
			return;
		}
		
		lyricsFrame->setText(TagLib::String([[self.metadata objectForKey:kMetadataLyricsKey] UTF8String], TagLib::String::UTF8));
		fileRef.tag()->addFrame(lyricsFrame);
	}

	// Comment
	if([self.metadata objectForKey:kMetadataCommentKey])
		fileRef.tag()->setComment(TagLib::String([[self.metadata objectForKey:kMetadataCommentKey] UTF8String], TagLib::String::UTF8));

	// ISRC
	if([self.metadata objectForKey:kMetadataISRCKey]) {
		textFrame = new TagLib::ID3v2::TextIdentificationFrame("TSRC", TagLib::String::Latin1);
		if(!textFrame) {
			self.error = [NSError errorWithDomain:NSPOSIXErrorDomain code:ENOMEM userInfo:nil];
			return;
		}
		
		textFrame->setText(TagLib::String([[self.metadata objectForKey:kMetadataISRCKey] UTF8String], TagLib::String::UTF8));
		fileRef.tag()->addFrame(textFrame);
	}
	
	// MCN frame?

	// MusicBrainz IDs
	if([self.metadata objectForKey:kMetadataMusicBrainzAlbumIDKey]) {
		TagLib::ID3v2::UserTextIdentificationFrame *userTextFrame = new TagLib::ID3v2::UserTextIdentificationFrame();
		if(!userTextFrame) {
			self.error = [NSError errorWithDomain:NSPOSIXErrorDomain code:ENOMEM userInfo:nil];
			return;
		}
		
		userTextFrame->setDescription(TagLib::String("MusicBrainz Album Id", TagLib::String::Latin1));
		userTextFrame->setText(TagLib::String([[self.metadata objectForKey:kMetadataMusicBrainzAlbumIDKey] UTF8String], TagLib::String::UTF8));
		
		fileRef.tag()->addFrame(userTextFrame);
	}
	
	if([self.metadata objectForKey:kMetadataMusicBrainzTrackIDKey]) {
		TagLib::ID3v2::UniqueFileIdentifierFrame *ufidFrame = new TagLib::ID3v2::UniqueFileIdentifierFrame(TagLib::String("http://musicbrainz.org", TagLib::String::Latin1), TagLib::ByteVector([[self.metadata objectForKey:kMetadataMusicBrainzTrackIDKey] UTF8String]));
		if(!ufidFrame) {
			self.error = [NSError errorWithDomain:NSPOSIXErrorDomain code:ENOMEM userInfo:nil];
			return;
		}
		
		fileRef.tag()->addFrame(ufidFrame);
	}
	
	// ReplayGain
	NSNumber *trackGain = [self.metadata valueForKey:kReplayGainTrackGainKey];
	NSNumber *trackPeak = [self.metadata valueForKey:kReplayGainTrackPeakKey];
	NSNumber *albumGain = [self.metadata valueForKey:kReplayGainAlbumGainKey];
	NSNumber *albumPeak = [self.metadata valueForKey:kReplayGainAlbumPeakKey];
	
	// Write TXXX frames
	TagLib::ID3v2::UserTextIdentificationFrame *trackGainFrame = TagLib::ID3v2::UserTextIdentificationFrame::find(fileRef.tag(), "replaygain_track_gain");
	TagLib::ID3v2::UserTextIdentificationFrame *trackPeakFrame = TagLib::ID3v2::UserTextIdentificationFrame::find(fileRef.tag(), "replaygain_track_peak");
	TagLib::ID3v2::UserTextIdentificationFrame *albumGainFrame = TagLib::ID3v2::UserTextIdentificationFrame::find(fileRef.tag(), "replaygain_album_gain");
	TagLib::ID3v2::UserTextIdentificationFrame *albumPeakFrame = TagLib::ID3v2::UserTextIdentificationFrame::find(fileRef.tag(), "replaygain_album_peak");
	
	if(trackGainFrame)
		fileRef.tag()->removeFrame(trackGainFrame);
	
	if(trackPeakFrame)
		fileRef.tag()->removeFrame(trackPeakFrame);
	
	if(albumGainFrame)
		fileRef.tag()->removeFrame(albumGainFrame);
	
	if(albumPeakFrame)
		fileRef.tag()->removeFrame(albumPeakFrame);
	
	if(trackGain) {
		TagLib::ID3v2::UserTextIdentificationFrame *userTextFrame = new TagLib::ID3v2::UserTextIdentificationFrame();
		if(!userTextFrame) {
			self.error = [NSError errorWithDomain:NSPOSIXErrorDomain code:ENOMEM userInfo:nil];
			return;
		}
		
		userTextFrame->setDescription(TagLib::String("replaygain_track_gain", TagLib::String::Latin1));
		userTextFrame->setText(TagLib::String([[NSString stringWithFormat:@"%+2.2f dB", [trackGain floatValue]] UTF8String], TagLib::String::UTF8));
		
		fileRef.tag()->addFrame(userTextFrame);
	}
	
	if(trackPeak) {
		TagLib::ID3v2::UserTextIdentificationFrame *userTextFrame = new TagLib::ID3v2::UserTextIdentificationFrame();
		if(!userTextFrame) {
			self.error = [NSError errorWithDomain:NSPOSIXErrorDomain code:ENOMEM userInfo:nil];
			return;
		}
		
		userTextFrame->setDescription(TagLib::String("replaygain_track_peak", TagLib::String::Latin1));
		userTextFrame->setText(TagLib::String([[NSString stringWithFormat:@"%1.8f dB", [trackPeak floatValue]] UTF8String], TagLib::String::UTF8));
		
		fileRef.tag()->addFrame(userTextFrame);
	}
	
	if(albumGain) {
		TagLib::ID3v2::UserTextIdentificationFrame *userTextFrame = new TagLib::ID3v2::UserTextIdentificationFrame();
		if(!userTextFrame) {
			self.error = [NSError errorWithDomain:NSPOSIXErrorDomain code:ENOMEM userInfo:nil];
			return;
		}
		
		userTextFrame->setDescription(TagLib::String("replaygain_album_gain", TagLib::String::Latin1));
		userTextFrame->setText(TagLib::String([[NSString stringWithFormat:@"%+2.2f dB", [albumGain floatValue]] UTF8String], TagLib::String::UTF8));
		
		fileRef.tag()->addFrame(userTextFrame);
	}
	
	if(albumPeak) {
		TagLib::ID3v2::UserTextIdentificationFrame *userTextFrame = new TagLib::ID3v2::UserTextIdentificationFrame();
		if(!userTextFrame) {
			self.error = [NSError errorWithDomain:NSPOSIXErrorDomain code:ENOMEM userInfo:nil];
			return;
		}
		
		userTextFrame->setDescription(TagLib::String("replaygain_album_peak", TagLib::String::Latin1));
		userTextFrame->setText(TagLib::String([[NSString stringWithFormat:@"%1.8f dB", [albumPeak floatValue]] UTF8String], TagLib::String::UTF8));
		
		fileRef.tag()->addFrame(userTextFrame);
	}
	
	// Also write the RVA2 frames
	fileRef.tag()->removeFrames("RVA2");
	if(trackGain) {
		TagLib::ID3v2::RelativeVolumeFrame *relativeVolumeFrame = new TagLib::ID3v2::RelativeVolumeFrame();
		if(!relativeVolumeFrame) {
			self.error = [NSError errorWithDomain:NSPOSIXErrorDomain code:ENOMEM userInfo:nil];
			return;
		}
		
		relativeVolumeFrame->setIdentification(TagLib::String("track", TagLib::String::Latin1));
		relativeVolumeFrame->setVolumeAdjustment([trackGain floatValue], TagLib::ID3v2::RelativeVolumeFrame::MasterVolume);
		
		fileRef.tag()->addFrame(relativeVolumeFrame);
	}
	
	if(albumGain) {
		TagLib::ID3v2::RelativeVolumeFrame *relativeVolumeFrame = new TagLib::ID3v2::RelativeVolumeFrame();
		if(!relativeVolumeFrame) {
			self.error = [NSError errorWithDomain:NSPOSIXErrorDomain code:ENOMEM userInfo:nil];
			return;
		}
		
		relativeVolumeFrame->setIdentification(TagLib::String("album", TagLib::String::Latin1));
		relativeVolumeFrame->setVolumeAdjustment([albumGain floatValue], TagLib::ID3v2::RelativeVolumeFrame::MasterVolume);
		
		fileRef.tag()->addFrame(relativeVolumeFrame);
	}
	
	// Album art
	if([self.metadata objectForKey:kAlbumArtFrontCoverKey]) {
		NSImage *image = [self.metadata objectForKey:kAlbumArtFrontCoverKey];
		NSData *imageData = [image PNGData];
		TagLib::ID3v2::AttachedPictureFrame *pictureFrame = new TagLib::ID3v2::AttachedPictureFrame();
		
		pictureFrame->setMimeType(TagLib::String("image/png", TagLib::String::Latin1));
		pictureFrame->setPicture(TagLib::ByteVector((const char *)[imageData bytes], (TagLib::uint)[imageData length]));

		fileRef.tag()->addFrame(pictureFrame);
	}
		
	// Application version
	NSString *appName = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleName"];
	NSString *shortVersionNumber = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleShortVersionString"];
	NSString *versionNumber = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleVersion"];	
	
	// Encoded by
	textFrame = new TagLib::ID3v2::TextIdentificationFrame("TENC", TagLib::String::Latin1);
	textFrame->setText(TagLib::String([[NSString stringWithFormat:@"%@ %@ (%@)", appName, shortVersionNumber, versionNumber] UTF8String], TagLib::String::UTF8));
	fileRef.tag()->addFrame(textFrame);
	
	// Encoding time
	textFrame = new TagLib::ID3v2::TextIdentificationFrame("TDEN", TagLib::String::Latin1);
	if(!textFrame) {
		self.error = [NSError errorWithDomain:NSPOSIXErrorDomain code:ENOMEM userInfo:nil];
		return;
	}
	
	NSString *timestamp = getID3v2Timestamp();
	
	textFrame->setText(TagLib::String([timestamp UTF8String], TagLib::String::UTF8));
	fileRef.tag()->addFrame(textFrame);
	
	// Tagging time
	textFrame = new TagLib::ID3v2::TextIdentificationFrame("TDTG", TagLib::String::Latin1);
	if(!textFrame) {
		self.error = [NSError errorWithDomain:NSPOSIXErrorDomain code:ENOMEM userInfo:nil];
		return;
	}

	timestamp = getID3v2Timestamp();
	
	textFrame->setText(TagLib::String([timestamp UTF8String], TagLib::String::UTF8));
	fileRef.tag()->addFrame(textFrame);
	
	if(!fileRef.save())
		self.error = [NSError errorWithDomain:NSPOSIXErrorDomain code:EIO userInfo:nil];
}

@end
