/*
 *  Copyright (C) 2008 - 2009 Stephen F. Booth <me@sbooth.org>
 *  All Rights Reserved
 */

#import "GeneralPreferencesViewController.h"

enum {
	kAlbumTitleMenuItem					= 1,
	kAlbumArtistMenuItem				= 2,
	kAlbumDateMenuItem					= 3,
	kTrackTitleMenuItem					= 4,
	kTrackArtistMenuItem				= 5,
	kTrackDateMenuItem					= 6,
	kTrackGenreMenuItem					= 7,
	kTrackComposerMenuItem				= 8,
	kDiscNumberMenuItemTag				= 9,
	kDiscTotalMenuItemTag				= 10,
	kTrackNumberMenuItemTag				= 11,
	kTrackTotalMenuItemTag				= 12
};

@implementation GeneralPreferencesViewController

- (id) init
{
	if((self = [super initWithNibName:@"GeneralPreferencesView" bundle:nil]))
		self.title = NSLocalizedString(@"General", @"The name of the general preference pane");
	
	return self;
}

- (void) awakeFromNib
{
	[[_customOutputFileFormatSpecifierPopUpButton selectedItem] setState:NSOffState];
	[_customOutputFileFormatSpecifierPopUpButton selectItemAtIndex:-1];
	[_customOutputFileFormatSpecifierPopUpButton synchronizeTitleAndSelectedItem];
}

- (IBAction) insertCustomOutputFileNamingFormatSpecifier:(id)sender
{
	NSParameterAssert(nil != sender);
	NSParameterAssert([sender isKindOfClass:[NSPopUpButton class]]);
	
	NSString *string = nil;
	
	switch([[sender selectedItem] tag]) {
		case kAlbumTitleMenuItem:			string = @"{albumTitle}";		break;
		case kAlbumArtistMenuItem:			string = @"{albumArtist}";		break;
		case kAlbumDateMenuItem:			string = @"{albumDate}";		break;
		case kTrackTitleMenuItem:			string = @"{trackTitle}";		break;
		case kTrackArtistMenuItem:			string = @"{trackArtist}";		break;
		case kTrackDateMenuItem:			string = @"{trackDate}";		break;
		case kTrackGenreMenuItem:			string = @"{trackGenre}";		break;
		case kTrackComposerMenuItem:		string = @"{trackComposer}";	break;
		case kDiscNumberMenuItemTag:		string = @"{discNumber}";		break;
		case kDiscTotalMenuItemTag:			string = @"{discTotal}";		break;
		case kTrackNumberMenuItemTag:		string = @"{trackNumber}";		break;
		case kTrackTotalMenuItemTag:		string = @"{trackTotal}";		break;
		default:							string = @"";					break;
	}
	
	// Replace the selected text with the token, if any is selected, otherwise just insert
	NSText *fieldEditor = [_customOutputFileNamingComboBox currentEditor];
	if(!fieldEditor) {
		[_customOutputFileNamingComboBox setStringValue:string];
		[_customOutputFileNamingComboBox sendAction:[_customOutputFileNamingComboBox action] to:[_customOutputFileNamingComboBox target]];
	}
	else if([_customOutputFileNamingComboBox textShouldBeginEditing:fieldEditor]) {
		[fieldEditor replaceCharactersInRange:[fieldEditor selectedRange] withString:string];
		[_customOutputFileNamingComboBox textShouldEndEditing:fieldEditor];
	}
}

- (IBAction) saveCustomOutputFileNamingFormat:(id)sender
{
	
#pragma unused(sender)
	
	NSString *pattern = [_customOutputFileNamingComboBox stringValue];
	
	NSMutableArray *patterns = [[[NSUserDefaults standardUserDefaults] stringArrayForKey:@"customOutputFileNamingPatterns"] mutableCopy];
	if(!patterns)
		patterns = [[NSMutableArray alloc] init];
	
	// Remove the pattern if it exists in the known patterns, so it can be repositioned at index 0
	[patterns removeObject:pattern];
	
	// Insert the new custom format string at index 0
	[patterns insertObject:pattern atIndex:0];
	
	// Only remember 10 custom filenaming patterns
	while(10 < [patterns count])
		[patterns removeLastObject];
	
	[[NSUserDefaults standardUserDefaults] setObject:patterns forKey:@"customOutputFileNamingPatterns"];
}

@end
