/*
 *  Copyright (C) 2007 - 2009 Stephen F. Booth <me@sbooth.org>
 *  All Rights Reserved
 */

#import <Cocoa/Cocoa.h>

// ========================================
// A HUD panel displaying information about a drive
// ========================================
@interface DriveInspectorPanelController : NSWindowController
{
@private
	id _inspectedDocument;
}

// ========================================
// Properties
@property (readonly, assign) id inspectedDocument;

// ========================================
// Action Methods
- (IBAction) toggleDriveInspectorPanel:(id)sender;

@end
