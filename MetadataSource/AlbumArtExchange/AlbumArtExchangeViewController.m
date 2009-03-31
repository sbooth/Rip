/*
 *  Copyright (C) 2009 Stephen F. Booth <me@sbooth.org>
 *  All Rights Reserved
 */

#import "AlbumArtExchangeViewController.h"
#import "AlbumArtExchangeInterface.h"
#import "AlbumArtExchangeImage.h"

#import <Quartz/Quartz.h>

@implementation AlbumArtExchangeViewController

@synthesize query = _query;

- (id) init
{
	return [super initWithNibName:@"AlbumArtExchangeView" bundle:[NSBundle bundleForClass:[AlbumArtExchangeInterface class]]];
}

- (void) awakeFromNib
{
	// The desired search term
	self.query = @"Slippery When Wet";

	// Automatically start searching
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
	NSLog(@"SEARCH:%@",sender);
	
	[_images removeAllObjects];
	[_imageBrowser reloadData];
	
	// Cancel any requests in progress
	if(_urlConnection) {
		[_urlConnection cancel], _urlConnection = nil;
		[_progressIndicator stopAnimation:sender];
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
		NSLog(@"fnord!!");
		return;
	}
	
	[_progressIndicator startAnimation:sender];
}

- (IBAction) useSelected:(id)sender
{

#pragma unused(sender)
	
	NSLog(@"useSelected");
}

- (IBAction) cancel:(id)sender
{
	// Cancel any requests in progress
	if(_urlConnection) {
		[_urlConnection cancel], _urlConnection = nil;
		[_progressIndicator stopAnimation:sender];
	}
	
	NSLog(@"cancel");
}

#pragma mark IKImageBrowserDataSource Protocol Methods

- (NSUInteger) numberOfItemsInImageBrowser:(IKImageBrowserView *)aBrowser
{
	
#pragma unused(aBrowser)
	
	return [_images count];
}

- (id) imageBrowser:(IKImageBrowserView *)aBrowser itemAtIndex:(NSUInteger)index
{

#pragma unused(aBrowser)
	NSLog(@"imageBrowser:objectAtIndex:%i [count = %i]",index,_images.count);
	return [_images objectAtIndex:index];
}

#pragma mark IKImageBrowserDelegate Protocol Methods

- (void) imageBrowserSelectionDidChange:(IKImageBrowserView *)aBrowser
{
	NSUInteger selectedIndex = [[aBrowser selectionIndexes] firstIndex];
	
	AlbumArtExchangeImage *image = [_images objectAtIndex:selectedIndex];
}

- (void) imageBrowser:(IKImageBrowserView *)aBrowser cellWasDoubleClickedAtIndex:(NSUInteger)index
{
	
#pragma unused(index)

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

	if([elementName isEqualToString:@"search-results"])
		_images = [NSMutableArray array];
	else if([elementName isEqualToString:@"image-info"])
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
