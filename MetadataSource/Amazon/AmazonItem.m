/*
 *  Copyright (C) 2009 Stephen F. Booth <me@sbooth.org>
 *  All Rights Reserved
 */

#import "AmazonItem.h"
#import <Quartz/Quartz.h>

@implementation AmazonItem

@synthesize ASIN = _ASIN;
@synthesize detailPageURL = _detailPageURL;
@synthesize smallImageURL = _smallImageURL;
@synthesize mediumImageURL = _mediumImageURL;
@synthesize largeImageURL = _largeImageURL;

#pragma mark IKImageBrowserItem Protocol Methods

- (NSString *) imageUID 
{
	return self.ASIN;
}

- (NSString *) imageRepresentationType
{
	return IKImageBrowserNSURLRepresentationType;
}

- (id) imageRepresentation
{
	if(self.smallImageURL)
		return self.smallImageURL;
	else if(self.mediumImageURL)
		return self.mediumImageURL;
	else if(self.largeImageURL)
		return self.largeImageURL;

	return nil;
}

- (NSString *) imageTitle
{
	return self.ASIN;
}

- (NSString *) description
{
	return [NSString stringWithFormat:@"AmazonItem (%x) {\n\tASIN: %@\n\tDetail Page: %@\n\tSmall Image: %@\n\tMedium Image: %@\n\tLarge Image: %@\n}", self, self.ASIN, self.detailPageURL, self.smallImageURL, self.mediumImageURL, self.largeImageURL];
}

@end
