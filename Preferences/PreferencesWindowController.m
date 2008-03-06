/*
 *  Copyright (C) 2008 Stephen F. Booth <me@sbooth.org>
 *  All Rights Reserved
 */

#import "PreferencesWindowController.h"
#import "EncoderManager.h"
#import "EncoderInterface/EncoderInterface.h"

@implementation PreferencesWindowController

- (id) init
{
	if((self = [super initWithWindowNibName:@"PreferencesWindow"])) {
		
	}
	return self;
}

- (void) awakeFromNib
{
	// Force an empty selection so the collection view will update properly
	[_arrayController setSelectionIndexes:[NSIndexSet indexSet]];
}

- (NSArray *) availableEncoders
{
	if(nil == _em)
		_em = [[EncoderManager alloc] init];

	NSMutableArray *encoders = [[NSMutableArray alloc] init];

	for(NSBundle *encoderBundle in _em.availableEncoders) {

		NSMutableDictionary *encoderDictionary = [[NSMutableDictionary alloc] init];

		NSString *encoderName = [encoderBundle objectForInfoDictionaryKey:@"EncoderName"];
		NSString *encoderVersion = [encoderBundle objectForInfoDictionaryKey:@"EncoderVersion"];
		NSString *encoderIconName = [encoderBundle objectForInfoDictionaryKey:@"EncoderIcon"];
		NSImage *encoderIcon = [NSImage imageNamed:encoderIconName];

		[encoderDictionary setObject:encoderBundle forKey:@"encoderBundle"];

		if(encoderName)
			[encoderDictionary setObject:encoderName forKey:@"encoderName"];
		if(encoderVersion)
			[encoderDictionary setObject:encoderVersion forKey:@"encoderVersion"];
		if(encoderIcon)
			[encoderDictionary setObject:encoderIcon forKey:@"encoderIcon"];			

		[encoders addObject:encoderDictionary];
	}
	
	return encoders;
}

- (IBAction) addEncoder:(id)sender
{

#pragma unused(sender)
	
	NSDictionary *encoderDictionary = [_arrayController.selectedObjects lastObject];
	NSLog(@"%@",encoderDictionary);
	
	NSBundle *encoderBundle = [encoderDictionary objectForKey:@"encoderBundle"];
	
	id <EncoderInterface> foo = [[[encoderBundle principalClass] alloc] init];
	NSDictionary *encoderDefaults = [foo defaultSettings];
	
	NSMutableArray *configuredEncoders = [[NSMutableArray alloc] initWithArray:[[NSUserDefaults standardUserDefaults] arrayForKey:@"configuredEncoders"]];
	
	NSMutableDictionary *encoder = [[NSMutableDictionary alloc] init];
	
	[encoder setObject:[encoderBundle bundleIdentifier] forKey:@"identifier"];
	if(encoderDefaults)
		[encoder setObject:encoderDefaults forKey:@"settings"];
	
	[configuredEncoders addObject:encoder];
	
	[[NSUserDefaults standardUserDefaults] setObject:configuredEncoders forKey:@"configuredEncoders"];
}

#pragma mark NSTableView Delegate Methods

/*- (void) tableView:(NSTableView *)aTableView willDisplayCell:(id)aCell forTableColumn:(NSTableColumn *)aTableColumn row:(NSInteger)rowIndex
{
	
#pragma unused(aTableView)
	
	if([aTableColumn.identifier isEqualToString:@"encoder"])
		[aCell setImage:[[_arrayController.arrangedObjects objectAtIndex:rowIndex] valueForKey:@"encoderIcon"]];
}*/

@end
