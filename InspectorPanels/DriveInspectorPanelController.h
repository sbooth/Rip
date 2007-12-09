/*
 *  Copyright (C) 2007 Stephen F. Booth <me@sbooth.org>
 *  All Rights Reserved
 */

#import <Cocoa/Cocoa.h>

@interface DriveInspectorPanelController : NSWindowController
{
	IBOutlet NSObjectController *_documentObjectController;
	id inspectedDocument;
}

@property id inspectedDocument;

- (IBAction) toggleDriveInspectorPanel:(id)sender;

@end
