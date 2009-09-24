/*
 *  Copyright (C) 2009 Stephen F. Booth <me@sbooth.org>
 *  All Rights Reserved
 */

#import "AmazonViewController.h"
#import "AmazonInterface.h"
#import "AmazonItem.h"
#import "NSString+URLEscapingMethods.h"

#import <MetadataSourceInterface/MetadataSourceData.h>
#import <MetadataSourceInterface/MetadataSourceDelegate.h>
#import <Quartz/Quartz.h>

// ========================================
// My amazon.com web services access ID
#define AWS_ACCESS_KEY_ID "18PZ5RH3H0X43PS96MR2"

static NSString *
queryStringComponentFromPair(NSString *field, NSString *value)
{
	NSCParameterAssert(nil != field);
	NSCParameterAssert(nil != value);
	
	return [NSString stringWithFormat:@"%@=%@", [field URLEscapedString], [value URLEscapedString]];
}

@interface AmazonViewController (Private)
- (MetadataSourceData *) metadataSourceData;
@end

@implementation AmazonViewController

@synthesize query = _query;

- (id) init
{
	if((self = [super initWithNibName:@"AmazonView" bundle:[NSBundle bundleForClass:[AmazonInterface class]]]))
		_items = [[NSMutableArray alloc] init];
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
	[_items removeAllObjects];
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
	NSString *urlBase = @"http://ecs.amazonaws.com/onca/xml";
	
	// Build up the query string
	NSMutableArray *queryComponents = [NSMutableArray array];

	[queryComponents addObject:queryStringComponentFromPair(@"Service", @"AWSECommerceService")];
	[queryComponents addObject:queryStringComponentFromPair(@"AWSAccessKeyId", @ AWS_ACCESS_KEY_ID)];
	[queryComponents addObject:queryStringComponentFromPair(@"Version", @"2009-02-01")];
	[queryComponents addObject:queryStringComponentFromPair(@"Operation", @"ItemSearch")];
	[queryComponents addObject:queryStringComponentFromPair(@"SearchIndex", @"Music")];
	[queryComponents addObject:queryStringComponentFromPair(@"ResponseGroup", @"Small,Images")];
	[queryComponents addObject:queryStringComponentFromPair(@"Keywords", self.query)];

	// Create the timestamp in XML dateTime format (omit milliseconds)
	NSCalendarDate *now = [NSCalendarDate calendarDate];
	[now setTimeZone:[NSTimeZone timeZoneWithName:@"GMT"]];
	[queryComponents addObject:queryStringComponentFromPair(@"Timestamp", [now descriptionWithCalendarFormat:@"%Y-%m-%dT%H:%M:%S.000Z"])];

	// Sort the parameters and form the canonical AWS query string
	[queryComponents sortUsingSelector:@selector(caseInsensitiveCompare:)];
	NSString *canonicalizedQueryString = [queryComponents componentsJoinedByString:@"&"];

	// Build the string which will be signed
	NSString *stringToSign = [NSString stringWithFormat:@"GET\necs.amazonaws.com\n/onca/xml\n%@", canonicalizedQueryString];
	
	// Calculate the HMAC for the string
	// This is done on a server to avoid revealing the secret key
	NSURL *signerURL = [NSURL URLWithString:@"http://sbooth.org/Rip/sign_aws_query.php"];
	NSMutableURLRequest *signerURLRequest = [NSMutableURLRequest requestWithURL:signerURL];
	[signerURLRequest setHTTPMethod:@"POST"];
	[signerURLRequest setValue:[[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleName"] forHTTPHeaderField:@"User-Agent"];
	[signerURLRequest setValue:@"application/x-www-form-urlencoded; charset=utf-8" forHTTPHeaderField:@"Content-Type"];

	NSString *postBody = [NSString stringWithFormat:@"string_to_sign=%@", [stringToSign URLEscapedString]];	
	[signerURLRequest setValue:[NSString stringWithFormat:@"%ld", [postBody length]] forHTTPHeaderField:@"Content-Length"];
	[signerURLRequest setHTTPBody:[postBody dataUsingEncoding:NSUTF8StringEncoding]];	
	
	NSHTTPURLResponse *signerResponse = nil;
	NSError *error = nil;
	NSData *digestData = [NSURLConnection sendSynchronousRequest:signerURLRequest returningResponse:&signerResponse error:&error];
	if(!digestData) {
		[self.view.window presentError:error modalForWindow:self.view.window delegate:nil didPresentSelector:NULL contextInfo:NULL];
		return;
	}
	
	NSString *digestString = [[NSString alloc] initWithData:digestData encoding:NSUTF8StringEncoding];
	
	// Append the signature to the request
	[queryComponents addObject:queryStringComponentFromPair(@"Signature", digestString)];

	// Build the query string and search URL
	NSString *queryString = [queryComponents componentsJoinedByString:@"&"];
	NSURL *searchURL = [NSURL URLWithString:[NSString stringWithFormat:@"%@?%@", urlBase, queryString]];

	// Set up the URL request
	NSURLRequest *request = [NSURLRequest requestWithURL:searchURL];
	
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
		AmazonItem *item = [_items objectAtIndex:selectedIndex];

		// Load the full size image
		NSURL *imageURL = item.largeImageURL;
		if(!imageURL)
			imageURL = item.mediumImageURL;
		if(!imageURL)
			imageURL = item.smallImageURL;
		
		NSImage *selectedImage = [[NSImage alloc] initWithContentsOfURL:imageURL];
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
	
	return [_items count];
}

- (id) imageBrowser:(IKImageBrowserView *)aBrowser itemAtIndex:(NSUInteger)itemIndex
{

#pragma unused(aBrowser)

	return [_items objectAtIndex:itemIndex];
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
	
//	NSLog(@"%@", [[NSString alloc] initWithBytes:[_responseData bytes] length:[_responseData length] encoding:NSUTF8StringEncoding]);
	
	// Let NSXMLDocument do the heavy lifting
	NSError *error = nil;
	NSXMLDocument *doc = [[NSXMLDocument alloc] initWithData:_responseData options:0 error:&error];
	if(!doc) {
		[self.view.window presentError:error modalForWindow:self.view.window delegate:nil didPresentSelector:NULL contextInfo:NULL];
		return;
	}

	// Extract all the returned items
	NSArray *items = [doc nodesForXPath:@".//Item" error:&error];
	if(!items) {
		[self.view.window presentError:error modalForWindow:self.view.window delegate:nil didPresentSelector:NULL contextInfo:NULL];
		return;
	}
	
	// And parse each one
	for(NSXMLNode *node in items) {
		AmazonItem *item = [[AmazonItem alloc] init];

		// Grab the ASIN
		NSArray *nodes = [node nodesForXPath:@"./ASIN" error:&error];
		item.ASIN = [[nodes lastObject] stringValue];

		// Detail page URL
		nodes = [node nodesForXPath:@"./DetailPageURL" error:&error];
		NSString *string = [[nodes lastObject] stringValue];
		if(string)
			item.detailPageURL = [NSURL URLWithString:string];

		// Images
		nodes = [node nodesForXPath:@"./SmallImage/URL" error:&error];
		string = [[nodes lastObject] stringValue];
		if(string)
			item.smallImageURL = [NSURL URLWithString:string];

		nodes = [node nodesForXPath:@"./MediumImage/URL" error:&error];
		string = [[nodes lastObject] stringValue];
		if(string)
			item.mediumImageURL = [NSURL URLWithString:string];

		nodes = [node nodesForXPath:@"./LargeImage/URL" error:&error];
		string = [[nodes lastObject] stringValue];
		if(string)
			item.largeImageURL = [NSURL URLWithString:string];

		// Only display items with associated photos
		if(item.smallImageURL || item.mediumImageURL || item.largeImageURL)
			[_items addObject:item];
	}
	
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

@end

@implementation AmazonViewController (Private)

- (MetadataSourceData *) metadataSourceData
{
	return (MetadataSourceData *)[self representedObject];
}

@end
