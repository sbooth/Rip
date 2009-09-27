/*
 *  Copyright (C) 2009 Stephen F. Booth <me@sbooth.org>
 *  All Rights Reserved
 */

#import <Cocoa/Cocoa.h>
#import <Quartz/Quartz.h>

@class AlbumArtExchangeImage;

// ========================================
// The meat & potatoes of the AlbumArtExchange.com metadata source
// Allows searching based on a specified search term as well as
// setting the disc's front cover image
// ========================================
@interface AlbumArtExchangeViewController : NSViewController //<NSXMLParserDelegate>
{
	IBOutlet IKImageBrowserView *_imageBrowser;
	IBOutlet NSProgressIndicator *_progressIndicator;
	IBOutlet NSButton *_useSelectedButton;

@private
	NSMutableArray *_images;
	NSString *_query;

	// HTTP connection state
	NSURLConnection *_urlConnection;
	NSMutableData *_responseData;
	
	// Parser state
	AlbumArtExchangeImage *_currentImage;
	NSMutableString *_currentStringValue;
}

// ========================================
// Properties
@property (copy) NSString * query;

// ========================================
// Action methods
- (IBAction) setZoom:(id)sender;
- (IBAction) search:(id)sender;

- (IBAction) useSelected:(id)sender;
- (IBAction) cancel:(id)sender;

@end
