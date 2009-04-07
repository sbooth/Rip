/*
 *  Copyright (C) 2009 Stephen F. Booth <me@sbooth.org>
 *  All Rights Reserved
 */

// ========================================
// Class encapsulating a single item from amazon.com
// Also implements the IKImageBrowserItem informal protocol
// ========================================
@interface AmazonItem : NSObject
{
@private
	NSString *_ASIN;	
	NSURL *_detailPageURL;
	NSURL *_smallImageURL;
	NSURL *_mediumImageURL;
	NSURL *_largeImageURL;
}

// ========================================
// Properties
@property (copy) NSString * ASIN;
@property (copy) NSURL * detailPageURL;
@property (copy) NSURL * smallImageURL;
@property (copy) NSURL * mediumImageURL;
@property (copy) NSURL * largeImageURL;

@end
