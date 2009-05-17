/*
 *  Copyright (C) 2009 Stephen F. Booth <me@sbooth.org>
 *  All Rights Reserved
 */

#import <Cocoa/Cocoa.h>

@interface ViewSelectorBarItem : NSObject
{
@private
	NSString *_identifier;
	NSString *_label;
	NSString *_tooltip;
	NSImage *_image;
	NSView *_view;
}

+ (id) itemWithIdentifier:(NSString *)identifier label:(NSString *)label tooltip:(NSString *)tooltip image:(NSImage *)image view:(NSView *)view;

@property (copy) NSString * identifier;
@property (copy) NSString * label;
@property (copy) NSString * tooltip;
@property (copy) NSImage * image;
@property (assign) NSView * view;

- (id) initWithIdentifier:(NSString *)identifier label:(NSString *)label tooltip:(NSString *)tooltip image:(NSImage *)image view:(NSView *)view;

@end
