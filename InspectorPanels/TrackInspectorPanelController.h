/*
 *  Copyright (C) 2007 - 2009 Stephen F. Booth <me@sbooth.org>
 *  All Rights Reserved
 */

#import <Cocoa/Cocoa.h>

@interface TrackInspectorPanelController : NSWindowController
{
@private
	id _inspectedDocument;
}

// ========================================
// Properties
// ========================================
@property (readonly, assign) id inspectedDocument;

// ========================================
// Action Methods
// ========================================
- (IBAction) toggleTrackInspectorPanel:(id)sender;

@end
