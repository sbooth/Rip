/*
 *  Copyright (C) 2009 Stephen F. Booth <me@sbooth.org>
 *  All Rights Reserved
 */

#import "MetadataViewController.h"

@interface MetadataViewController (Private)
- (void) toggleTableColumnVisible:(id)sender;
@end

@implementation MetadataViewController

- (id) init
{
	return [super initWithNibName:@"MetadataView" bundle:nil];
}

- (void) awakeFromNib
{
	// Create the menu for the table's header, to allow showing and hiding of columns
	NSMenu *menu = [[NSMenu alloc] initWithTitle:NSLocalizedString(@"Track Table Columns", @"")];
	NSSortDescriptor *tableColumnsNameSortDescriptor = [[NSSortDescriptor alloc] initWithKey:@"headerCell.title" ascending:YES];
	NSArray *sortedTableColumns = [_trackTable.tableColumns sortedArrayUsingDescriptors:[NSArray arrayWithObject:tableColumnsNameSortDescriptor]];
	for(NSTableColumn *column in sortedTableColumns) {
		NSMenuItem *menuItem = [menu addItemWithTitle:[column.headerCell title]
											   action:@selector(toggleTableColumnVisible:) 
										keyEquivalent:@""];
		[menuItem setTarget:self];
		[menuItem setRepresentedObject:column];
		[menuItem setState:!column.isHidden];
	}
	[_trackTable.headerView setMenu:menu];
	
	// Set the default sort descriptors for the track table
	NSSortDescriptor *trackNumberSortDescriptor = [[NSSortDescriptor alloc] initWithKey:@"number" ascending:YES];
	[_trackController setSortDescriptors:[NSArray arrayWithObject:trackNumberSortDescriptor]];
}

#pragma mark NSTableView Delegate Methods

- (void) tableView:(NSTableView *)aTableView willDisplayCell:(id)aCell forTableColumn:(NSTableColumn *)aTableColumn row:(NSInteger)rowIndex
{
	
#pragma unused(aTableView)
	
	if([aTableColumn.identifier isEqualToString:@"isSelected"])
		[aCell setTitle:[[[[_trackController arrangedObjects] objectAtIndex:rowIndex] valueForKey:@"number"] stringValue]];
}

@end

@implementation MetadataViewController (Private)

- (void) toggleTableColumnVisible:(id)sender
{
	NSParameterAssert(nil != sender);
	NSParameterAssert([sender isKindOfClass:[NSMenuItem class]]);
	
	NSMenuItem *menuItem = (NSMenuItem *)sender;
	NSTableColumn *column = menuItem.representedObject;
	
	[column setHidden:!column.isHidden];
	[menuItem setState:!column.isHidden];
}

@end
