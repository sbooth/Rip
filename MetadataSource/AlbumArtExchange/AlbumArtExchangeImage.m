/*
 *  Copyright (C) 2009 Stephen F. Booth <me@sbooth.org>
 *  All Rights Reserved
 */

#import "AlbumArtExchangeImage.h"
#import <Quartz/Quartz.h>

@implementation AlbumArtExchangeImage

@synthesize imageID = _imageID;
@synthesize thumbnailURL = _thumbnailURL;
@synthesize imageURL = _imageURL;
@synthesize imageDirectURL = _imageDirectURL;
@synthesize imageDimensions = _imageDimensions;
@synthesize imageFileSize = _imageFileSize;
@synthesize imageFormat = _imageFormat;
@synthesize galleryURL = _galleryURL;
@synthesize whereToBuy = _whereToBuy;
@synthesize title = _title;
@synthesize artist = _artist;
@synthesize composer = _composer;
@synthesize dateAdded = _dateAdded;
@synthesize rating = _rating;
@synthesize viewCount = _viewCount;
@synthesize poster = _poster;

#pragma mark IKImageBrowserItem Protocol Methods

- (NSString *) imageUID 
{
	return [self.imageURL absoluteString];
}

- (NSString *) imageRepresentationType
{
	return IKImageBrowserNSURLRepresentationType;
}

- (id) imageRepresentation
{
	return self.thumbnailURL;
}

- (NSString *) imageTitle
{
	return [NSString stringWithFormat:NSLocalizedString(@"%@ - %@", @""), self.title, self.artist];
}

- (NSString *) imageSubtitle
{
	NSString *sizeString = [NSString stringWithFormat:NSLocalizedString(@"%ld x %ld", @""), (NSUInteger)self.imageDimensions.width, (NSUInteger)self.imageDimensions.height];
	return [NSString stringWithFormat:NSLocalizedString(@"%@,  %@", @""), sizeString, self.imageFormat];
}

@end
