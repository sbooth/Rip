/*
 *  Copyright (C) 2009 Stephen F. Booth <me@sbooth.org>
 *  All Rights Reserved
 */

#import <Cocoa/Cocoa.h>

#define INSPECTOR_PANE_HEADER_HEIGHT 17

@class InspectorPaneHeader, InspectorPaneBody;

extern NSString * const InspectorPaneDidCollapseNotification;
extern NSString * const InspectorPaneDidExpandNotification;

@interface InspectorPane : NSView
{
@private
	BOOL _collapsed;
	InspectorPaneHeader *_headerView;
	InspectorPaneBody *_bodyView;
}

@property (assign, getter=isCollapsed) BOOL collapsed;

- (NSString *) title;
- (void) setTitle:(NSString *)title;

- (IBAction) toggleCollapsed:(id)sender;

- (InspectorPaneHeader *) headerView;
- (InspectorPaneBody *) bodyView;

@end
