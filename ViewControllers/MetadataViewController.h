/*
 *  Copyright (C) 2009 Stephen F. Booth <me@sbooth.org>
 *  All Rights Reserved
 */

#import <Cocoa/Cocoa.h>

@interface MetadataViewController : NSViewController
{
	IBOutlet NSArrayController *_trackController;
	IBOutlet NSTableView *_trackTable;
}

@end
