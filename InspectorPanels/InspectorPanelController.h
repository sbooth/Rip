/*
 *  Copyright (C) 2009 Stephen F. Booth <me@sbooth.org>
 *  All Rights Reserved
 */

#import <Cocoa/Cocoa.h>

@class SFBInspectorView;

@interface InspectorPanelController : NSWindowController
{
	IBOutlet SFBInspectorView * _inspectorView;

@private
	id _inspectedDocument;
}

// ========================================
// Properties
@property (readonly, assign) id inspectedDocument;

// ========================================
// Action Methods
- (IBAction) toggleInspectorPanel:(id)sender;

@end
