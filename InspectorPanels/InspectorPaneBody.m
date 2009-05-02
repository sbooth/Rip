/*
 *  Copyright (C) 2009 Stephen F. Booth <me@sbooth.org>
 *  All Rights Reserved
 */

#import "InspectorPaneBody.h"

@interface InspectorPaneBody ()
@property (assign) CGFloat normalHeight;
@end

@implementation InspectorPaneBody

@synthesize normalHeight = _normalHeight;

- (id) initWithFrame:(NSRect)frameRect
{
	if((self = [super initWithFrame:frameRect]))
		self.normalHeight = frameRect.size.height;
	return self;
}

- (BOOL) acceptsFirstMouse:(NSEvent *)theEvent
{

#pragma unused(theEvent)
	
	return YES;
}

@end
