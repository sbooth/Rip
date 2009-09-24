/*
 *  Copyright (C) 2009 Stephen F. Booth <me@sbooth.org>
 *  All Rights Reserved
 */

#import "AlbumArtExchangeViewController.h"
#import "AlbumArtExchangeInterface.h"
#import "AlbumArtExchangeImage.h"

#import <MetadataSourceInterface/MetadataSourceData.h>
#import <MetadataSourceInterface/MetadataSourceDelegate.h>
#import <Quartz/Quartz.h>

@interface AlbumArtExchangeViewController (Private)
- (MetadataSourceData *) metadataSourceData;
@end

@implementation AlbumArtExchangeViewController

@synthesize query = _query;

- (id) init
{
	if((self = [super initWithNibName:@"AlbumArtExchangeView" bundle:[NSBundle bundleForClass:[AlbumArtExchangeInterface class]]]))
		_images = [[NSMutableArray alloc] init];
	return self;
}

- (void) awakeFromNib
{
	// For some reason this flag doesn't stick in IB
	[_imageBrowser setAllowsMultipleSelection:NO];
	
	// Set the initial search term
	MetadataSourceData *data = [self metadataSourceData];
	NSString *albumTitle = [data.metadata objectForKey:kMetadataTitleKey];
	NSString *albumArtist = [data.metadata objectForKey:kMetadataArtistKey];

	if(albumTitle && albumArtist)
		self.query = [NSString stringWithFormat:@"%@ %@", albumArtist, albumTitle];
	else if(albumTitle)
		self.query = albumTitle;
	else if(albumArtist)
		self.query = albumArtist;

	// Automatically start searching
	if([self.query length])
		[self search:self];
}

- (IBAction) setZoom:(id)sender
{
	if([sender respondsToSelector:@selector(floatValue)]) {
		[_imageBrowser setZoomValue:[sender floatValue]];
		[_imageBrowser setNeedsDisplay:YES];
	}
}

- (IBAction) search:(id)sender
{
	[_images removeAllObjects];
	[_imageBrowser reloadData];
	
	// Cancel any requests in progress
	if(_urlConnection) {
		[_urlConnection cancel], _urlConnection = nil;
		[_progressIndicator stopAnimation:sender];
	}

	if(![self.query length]) {
		NSBeep();
		return;
	}

	// All searches start at this URL
	NSURL *searchURL = [NSURL URLWithString:@"http://www.albumartexchange.com/search.php"];
	
	// Set up the URL request; use POST because it is easier to set up the arguments
	NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:searchURL];
	NSString *requestBody = [NSString stringWithFormat:@"q=%@", [self.query stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding]];
	[request setHTTPMethod:@"POST"];
	[request setHTTPBody:[requestBody dataUsingEncoding:NSUTF8StringEncoding]];
	
	// Go get 'em!
	_urlConnection = [[NSURLConnection alloc] initWithRequest:request delegate:self];
	if(!_urlConnection) {
		NSLog(@"Unable to create NSURLConnection");
		return;
	}
	
	[_progressIndicator startAnimation:sender];
}

- (IBAction) useSelected:(id)sender
{

#pragma unused(sender)
	
	// Save the selected image, if there is a selection
	NSIndexSet *selectionIndexes = [_imageBrowser selectionIndexes];
	if([selectionIndexes count]) {
		NSUInteger selectedIndex = [selectionIndexes firstIndex];	
		AlbumArtExchangeImage *image = [_images objectAtIndex:selectedIndex];
		// Load the full size image
		NSImage *selectedImage = [[NSImage alloc] initWithContentsOfURL:image.imageURL];
		if(selectedImage) {
			NSMutableDictionary *metadata = [[[self metadataSourceData] metadata] mutableCopy];
			[metadata setObject:selectedImage forKey:kAlbumArtFrontCoverKey];
			[[self metadataSourceData] setMetadata:metadata];
		}		
	}
	
	[[[self metadataSourceData] delegate] metadataSourceViewController:self finishedWithReturnCode:NSOKButton];
}

- (IBAction) cancel:(id)sender
{
	// Cancel any requests in progress
	if(_urlConnection) {
		[_urlConnection cancel], _urlConnection = nil;
		[_progressIndicator stopAnimation:sender];
	}
	
	[[[self metadataSourceData] delegate] metadataSourceViewController:self finishedWithReturnCode:NSCancelButton];
}

#pragma mark IKImageBrowserDataSource Protocol Methods

- (NSUInteger) numberOfItemsInImageBrowser:(IKImageBrowserView *)aBrowser
{
	
#pragma unused(aBrowser)
	
	return [_images count];
}

- (id) imageBrowser:(IKImageBrowserView *)aBrowser itemAtIndex:(NSUInteger)itemIndex
{

#pragma unused(aBrowser)

	return [_images objectAtIndex:itemIndex];
}

#pragma mark IKImageBrowserDelegate Protocol Methods

- (void) imageBrowserSelectionDidChange:(IKImageBrowserView *)aBrowser
{
	NSIndexSet *selectionIndexes = [aBrowser selectionIndexes];
	[_useSelectedButton setEnabled:(0 != [selectionIndexes count])];
}

- (void) imageBrowser:(IKImageBrowserView *)aBrowser cellWasDoubleClickedAtIndex:(NSUInteger)itemIndex
{
	
#pragma unused(itemIndex)

	[self useSelected:aBrowser];
}

#pragma mark NSURLRequest Delegate Methods

- (void) connection:(NSURLConnection *)connection didReceiveResponse:(NSURLResponse *)response
{

#pragma unused(connection)
#pragma unused(response)
	
	// Allocate the object to hold the received data
    _responseData = [NSMutableData data];
}

- (void) connection:(NSURLConnection *)connection didReceiveData:(NSData *)data
{

#pragma unused(connection)

	// Just save the data we've received so far
    [_responseData appendData:data];
}

- (void) connectionDidFinishLoading:(NSURLConnection *)connection
{

#pragma unused(connection)

	// Parse the results
	NSXMLParser *parser = [[NSXMLParser alloc] initWithData:_responseData];
	[parser setDelegate:self];
	
	/*BOOL success =*/ [parser parse];
	
	// And load them into the browser
	[_imageBrowser reloadData];
	
	[_progressIndicator stopAnimation:self];
	
	// Clean up
	_urlConnection = nil;
    _responseData = nil;
}

- (void) connection:(NSURLConnection *)connection didFailWithError:(NSError *)error
{
	
#pragma unused(connection)
	
	// Bummer
	[_progressIndicator stopAnimation:self];
	
    // Inform the user
	[self.view.window presentError:error modalForWindow:self.view.window delegate:nil didPresentSelector:NULL contextInfo:NULL];

	_urlConnection = nil;
    _responseData = nil;
}

#pragma mark NSXMLParser Delegate Methods

- (void) parser:(NSXMLParser *)parser didStartElement:(NSString *)elementName namespaceURI:(NSString *)namespaceURI qualifiedName:(NSString *)qName attributes:(NSDictionary *)attributeDict
{

#pragma unused(parser)
#pragma unused(namespaceURI)
#pragma unused(qName)
#pragma unused(attributeDict)

	_currentStringValue = [NSMutableString string];

	if([elementName isEqualToString:@"image-info"])
		_currentImage = [[AlbumArtExchangeImage alloc] init];
}

- (void) parser:(NSXMLParser *)parser foundCharacters:(NSString *)string
{

#pragma unused(parser)
	
	[_currentStringValue appendString:string];
}

- (void) parser:(NSXMLParser *)parser didEndElement:(NSString *)elementName namespaceURI:(NSString *)namespaceURI qualifiedName:(NSString *)qName
{

#pragma unused(parser)
#pragma unused(namespaceURI)
#pragma unused(qName)
	
	// Handle image elements
	if([elementName isEqualToString:@"id"])
		_currentImage.imageID = [_currentStringValue integerValue];
	else if([elementName isEqualToString:@"image"])
		_currentImage.imageURL = [NSURL URLWithString:_currentStringValue];
	else if([elementName isEqualToString:@"image-direct"])
		_currentImage.imageDirectURL = [NSURL URLWithString:_currentStringValue];
	else if([elementName isEqualToString:@"file-size"])
		_currentImage.imageFileSize = [_currentStringValue integerValue];
	else if([elementName isEqualToString:@"width"]) {
		NSSize currentSize = _currentImage.imageDimensions;
		currentSize.width = [_currentStringValue floatValue];
		_currentImage.imageDimensions = currentSize;
	}
	else if([elementName isEqualToString:@"height"]) {
		NSSize currentSize = _currentImage.imageDimensions;
		currentSize.height = [_currentStringValue floatValue];
		_currentImage.imageDimensions = currentSize;
	}
	else if([elementName isEqualToString:@"format"])
		_currentImage.imageFormat = [_currentStringValue copy];
	else if([elementName isEqualToString:@"thumbnail"])
		_currentImage.thumbnailURL = [NSURL URLWithString:_currentStringValue];
	else if([elementName isEqualToString:@"gallery-page"])
		_currentImage.galleryURL = [NSURL URLWithString:_currentStringValue];
	else if([elementName isEqualToString:@"title"])
		_currentImage.title = [_currentStringValue copy];
	else if([elementName isEqualToString:@"artist"])
		_currentImage.artist = [_currentStringValue copy];
	else if([elementName isEqualToString:@"composer"])
		_currentImage.composer = [_currentStringValue copy];
	else if([elementName isEqualToString:@"date-added"])
		_currentImage.dateAdded = [NSDate dateWithString:_currentStringValue];
	else if([elementName isEqualToString:@"where-to-buy"])
		_currentImage.whereToBuy = [NSURL URLWithString:_currentStringValue];
	else if([elementName isEqualToString:@"rating"])
		_currentImage.rating = [_currentStringValue integerValue];
	else if([elementName isEqualToString:@"view-count"])
		;
	else if([elementName isEqualToString:@"poster"])
		_currentImage.poster = [_currentStringValue copy];
	// Save the image
	else if([elementName isEqualToString:@"image-info"]) {
		[_images addObject:_currentImage];
		
		// Reset for the next one
		_currentImage = nil;
	}

	_currentStringValue = nil;
}

- (void) parser:(NSXMLParser *)parser parseErrorOccurred:(NSError *)parseError
{

#pragma unused(parser)
	
	[self.view.window presentError:parseError modalForWindow:self.view.window delegate:nil didPresentSelector:NULL contextInfo:NULL];
}

@end

@implementation AlbumArtExchangeViewController (Private)

- (MetadataSourceData *) metadataSourceData
{
	return (MetadataSourceData *)[self representedObject];
}

@end
