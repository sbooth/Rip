/*
 *  Copyright (C) 2007 Stephen F. Booth <me@sbooth.org>
 *  All Rights Reserved
 */

#import <Cocoa/Cocoa.h>

@interface TrackInspectorPanelController : NSWindowController
{
	IBOutlet NSObjectController *_documentObjectController;
	id inspectedDocument;
}

@property id inspectedDocument;

- (IBAction) toggleTrackInspectorPanel:(id)sender;

@end
