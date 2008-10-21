/*
 *  Copyright (C) 2007 - 2008 Stephen F. Booth <me@sbooth.org>
 *  All Rights Reserved
 */

#import <Cocoa/Cocoa.h>

@interface DiscInspectorPanelController : NSWindowController
{
	IBOutlet NSObjectController *_documentObjectController;

@private
	id _inspectedDocument;
}

@property (readonly, assign) id inspectedDocument;

- (IBAction) toggleDiscInspectorPanel:(id)sender;

@end
