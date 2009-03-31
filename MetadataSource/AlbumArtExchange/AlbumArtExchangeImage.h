/*
 *  Copyright (C) 2009 Stephen F. Booth <me@sbooth.org>
 *  All Rights Reserved
 */

// ========================================
// Class encapsulating a single image resource from AlbumArtExchange.com
// Also implements the IKImageBrowserItem informal protocol
// ========================================
@interface AlbumArtExchangeImage : NSObject
{
@private
	NSInteger _imageID;
	NSURL *_thumbnailURL;
	NSURL *_imageURL;
	NSURL *_imageDirectURL;
	NSSize _imageDimensions;
	NSInteger _imageFileSize;
	NSString *_imageFormat;
	NSURL *_galleryURL;
	NSURL *_whereToBuy;
	NSString *_title;
	NSString *_artist;
	NSString *_composer;
	NSDate *_dateAdded;
	NSInteger _rating;
	NSInteger _viewCount;
	NSString *_poster;
}

// ========================================
// Properties
@property (assign) NSInteger imageID;

@property (copy) NSURL * thumbnailURL;
@property (copy) NSURL * imageURL;
@property (copy) NSURL * imageDirectURL;
@property (assign) NSSize imageDimensions;
@property (assign) NSInteger imageFileSize;
@property (copy) NSString * imageFormat;

@property (copy) NSURL * galleryURL;
@property (copy) NSURL * whereToBuy;

@property (copy) NSString * title;
@property (copy) NSString * artist;
@property (copy) NSString * composer;

@property (copy) NSDate * dateAdded;
@property (assign) NSInteger rating;
@property (assign) NSInteger viewCount;

@property (copy) NSString * poster;

@end
