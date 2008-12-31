/*
 *  Copyright (C) 2008 Stephen F. Booth <me@sbooth.org>
 *  All Rights Reserved
 */

#import "NSImage+BitmapRepresentationMethods.h"

@implementation NSImage (BitmapRepresentationMethods)

- (NSData *) PNGData
{
	return [self bitmapDataForImageFileType:NSPNGFileType];
}

- (NSData *) bitmapDataForImageFileType:(NSBitmapImageFileType)imageFileType
{
	NSBitmapImageRep *bitmapRep = nil;
	
	for(NSImageRep *currentRepresentation in [self representations]) {
		if([currentRepresentation isKindOfClass:[NSBitmapImageRep class]]) {
			bitmapRep = (NSBitmapImageRep *)currentRepresentation;
			break;
		}
	}
	
	// Create a bitmap representation if one doesn't exist
	if(!bitmapRep) {
		NSSize size = [self size];
		[self lockFocus];
		bitmapRep = [[NSBitmapImageRep alloc] initWithFocusedViewRect:NSMakeRect(0, 0, size.width, size.height)];
		[self unlockFocus];
	}
	
	return [bitmapRep representationUsingType:imageFileType properties:nil]; 
}

@end
