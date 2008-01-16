/*
 *  Copyright (C) 2007 Stephen F. Booth <me@sbooth.org>
 *  All Rights Reserved
 */

#import <Cocoa/Cocoa.h>

@interface TrackInspectorPanelController : NSWindowController
{
	IBOutlet NSObjectController *_documentObjectController;

@private
	id _inspectedDocument;
}

@property (readonly, assign) id inspectedDocument;

- (IBAction) toggleTrackInspectorPanel:(id)sender;

@end
