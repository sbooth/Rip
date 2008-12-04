/*
 *  Copyright (C) 2008 Stephen F. Booth <me@sbooth.org>
 *  All Rights Reserved
 */

#import "EncoderWindowController.h"

#import "EncoderManager.h"
#import <EncoderInterface/EncodingOperation.h>

// ========================================
// Context objects for observeValueForKeyPath:ofObject:change:context:
// ========================================
static NSString * const kEncoderOperationQueueKVOContext		= @"org.sbooth.Rip.EncoderWindowController.EncoderOperationQueue.KVOContext";

@implementation EncoderWindowController

- (id) init
{
	if((self = [super initWithWindowNibName:@"EncoderWindow"])) {
		[[EncoderManager sharedEncoderManager] addObserver:self forKeyPath:@"queue.operations" options:(NSKeyValueObservingOptionOld|NSKeyValueObservingOptionNew) context:kEncoderOperationQueueKVOContext];
	}
	return self;
}

- (void) awakeFromNib
{
	NSPathCell *pathCell = [[NSPathCell alloc] init];
	[pathCell setPathStyle:NSPathStylePopUp];
	[pathCell setControlSize:NSSmallControlSize];
	[pathCell setEditable:NO];
	[[[_tableView tableColumns] objectAtIndex:0] setDataCell:pathCell];
}

- (void) observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context
{
    if(kEncoderOperationQueueKVOContext == context) {
		NSInteger changeKind = [[change objectForKey:NSKeyValueChangeKindKey] integerValue];
		
		if(NSKeyValueChangeInsertion == changeKind) {
			for(NSOperation *operation in [change objectForKey:NSKeyValueChangeNewKey]) {
				if([operation isKindOfClass:[EncodingOperation class]])
					[_arrayController addObject:operation];
			}
		}
		else if(NSKeyValueChangeRemoval == changeKind) {
			for(NSOperation *operation in [change objectForKey:NSKeyValueChangeOldKey]) {
				if([operation isKindOfClass:[EncodingOperation class]])
					[_arrayController removeObject:operation];
			}
		}
	}
	else
		[super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
}

- (IBAction) toggleEncoderWindow:(id)sender
{
    NSWindow *window = self.window;
	
	if(window.isVisible && window.isKeyWindow)
		[window orderOut:sender];
	else
		[window makeKeyAndOrderFront:sender];
}

- (BOOL) validateMenuItem:(NSMenuItem *)menuItem
{
	if([menuItem action] == @selector(toggleEncoderWindow:)) {
		NSString *menuTitle = nil;
		
		if(!self.isWindowLoaded || !self.window.isVisible || !self. window.isKeyWindow)
			menuTitle = NSLocalizedString(@"Show Encoder", @"Menu Item");
		else
			menuTitle = NSLocalizedString(@"Hide Encoder", @"Menu Item");
		
		[menuItem setTitle:menuTitle];
	}
	
	return YES;
}

@end
