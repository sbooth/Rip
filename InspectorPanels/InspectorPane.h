/*
 *  Copyright (C) 2009 Stephen F. Booth <me@sbooth.org>
 *  All Rights Reserved
 */

#import <Cocoa/Cocoa.h>

#define INSPECTOR_PANE_HEADER_HEIGHT 17

@class InspectorPaneHeader, InspectorPaneBody;

@interface InspectorPane : NSView
{
@private
	BOOL _collapsed;
	InspectorPaneHeader *_headerView;
	InspectorPaneBody *_bodyView;
}

@property (readonly, assign, getter=isCollapsed) BOOL collapsed;

- (NSString *) title;
- (void) setTitle:(NSString *)title;

- (IBAction) toggleCollapsed:(id)sender;
- (void) setCollapsed:(BOOL)collapsed animate:(BOOL)animate;

- (InspectorPaneHeader *) headerView;
- (InspectorPaneBody *) bodyView;

@end
