/*
 *  Copyright (C) 2007 - 2008 Stephen F. Booth <me@sbooth.org>
 *  All Rights Reserved
 */

#import "ApplicationDelegate.h"
#import "ByteSizeValueTransformer.h"
#import "DurationValueTransformer.h"
#import "CompactDiscWindowController.h"
#import "CompactDisc.h"
#import "DriveInformation.h"
#import "EncoderManager.h"
#import "MusicDatabaseManager.h"
#import "ReadOffsetCalculatorSheetController.h"
#import "Logger.h"

#import "MusicDatabaseInterface/MusicDatabaseInterface.h"
#import "MusicDatabaseInterface/MusicDatabaseQueryOperation.h"
#import "MusicDatabaseInterface/MusicDatabaseSubmissionOperation.h"

#include <CoreFoundation/CoreFoundation.h>
#include <DiskArbitration/DiskArbitration.h>

#include <IOKit/IOKitLib.h>
#include <IOKit/storage/IOCDMedia.h>

// ========================================
// Class extensions
// ========================================

@interface ApplicationDelegate ()
@property (assign) NSPersistentStoreCoordinator * persistentStoreCoordinator;
@property (assign) NSPersistentStore * primaryStore;
@property (assign) NSPersistentStore * inMemoryStore;
@property (assign) NSManagedObjectModel * managedObjectModel;
@property (assign) NSManagedObjectContext * managedObjectContext;
@end


// ========================================
// Private methods for the ApplicationDelegate class
// ========================================

@interface ApplicationDelegate (Private)
- (void) diskAppeared:(DADiskRef)disk;
- (void) diskDisappeared:(DADiskRef)disk;
- (void) handleGetURLAppleEvent:(NSAppleEventDescriptor *)event withReplyEvent:(NSAppleEventDescriptor *)replyEvent;
- (void) readOffsetKnownSheetDidEnd:(NSWindow *)sheet returnCode:(NSInteger)returnCode contextInfo:(void *)contextInfo;
- (void) readOffsetNotConfiguredSheetDidEnd:(NSWindow *)sheet returnCode:(NSInteger)returnCode contextInfo:(void *)contextInfo;
@end


// ========================================
// DiskArbitration callbacks
// ========================================

#pragma mark DiskArbitration callback functions

static void diskAppearedCallback(DADiskRef disk, void *context);
static void diskDisappearedCallback(DADiskRef disk, void *context);

static void 
diskAppearedCallback(DADiskRef disk, void *context)
{
	NSCParameterAssert(NULL != context);
	
	[(ApplicationDelegate *)context diskAppeared:disk];
}

static void 
diskDisappearedCallback(DADiskRef disk, void *context)
{
	NSCParameterAssert(NULL != context);
	
	[(ApplicationDelegate *)context diskDisappeared:disk];
}

@implementation ApplicationDelegate

+ (void) initialize
{
	// Register reasonable defaults for most preferences
	NSMutableDictionary *defaultsDictionary = [NSMutableDictionary dictionary];

	[defaultsDictionary setObject:[NSNumber numberWithInteger:1] forKey:@"preferencesVersion"];
	[defaultsDictionary setObject:[NSNumber numberWithInteger:5] forKey:@"maxRetries"];
	[defaultsDictionary setObject:[NSNumber numberWithInteger:3] forKey:@"requiredMatches"];
	[defaultsDictionary setObject:[NSNumber numberWithBool:NO] forKey:@"useCustomOutputFileNaming"];

	NSURL *musicFolderURL = [NSURL URLWithString:[@"~/Music" stringByExpandingTildeInPath]];
	[defaultsDictionary setObject:[NSArchiver archivedDataWithRootObject:musicFolderURL] forKey:@"outputDirectory"];
	
	[defaultsDictionary setObject:[NSNumber numberWithInteger:eExistingOutputFileHandlingRename] forKey:@"existingOutputFileHandling"];
	[defaultsDictionary setObject:[NSNumber numberWithInteger:eLogMessageLevelNormal] forKey:@"logMessageLevel"];
	
	[defaultsDictionary setObject:[NSNumber numberWithBool:YES] forKey:@"automaticallyQueryAccurateRip"];
	[defaultsDictionary setObject:[NSNumber numberWithBool:YES] forKey:@"automaticallyQueryMusicDatabase"];
	
	[defaultsDictionary setObject:@"org.sbooth.Rip.MusicDatabase.MusicBrainz" forKey:@"defaultMusicDatabase"];
	[defaultsDictionary setObject:@"org.sbooth.Rip.Encoder.FLAC" forKey:@"defaultEncoder"];
	
	// Enable Sparkle system profiling
	[defaultsDictionary setObject:[NSNumber numberWithBool:YES] forKey:@"SUEnableSystemProfiling"];
	
	[[NSUserDefaults standardUserDefaults] registerDefaults:defaultsDictionary];
	
	// Register custom value transformer classes
	NSValueTransformer *transformer = nil;
	
	transformer = [[ByteSizeValueTransformer alloc] init];
	[NSValueTransformer setValueTransformer:transformer forName:@"ByteSizeValueTransformer"];
	
	transformer = [[DurationValueTransformer alloc] init];
	[NSValueTransformer setValueTransformer:transformer forName:@"DurationValueTransformer"];
}

@synthesize persistentStoreCoordinator = _persistentStoreCoordinator;
@synthesize primaryStore = _primaryStore;
@synthesize inMemoryStore = _inMemoryStore;
@synthesize managedObjectModel = _managedObjectModel;
@synthesize managedObjectContext = _managedObjectContext;

// Don't automatically open an untitled document
- (BOOL) applicationShouldOpenUntitledFile:(NSApplication *)sender
{
	
#pragma unused(sender)
	
	return NO;
}

- (void) applicationWillFinishLaunching:(NSNotification *)aNotification
{
	
#pragma unused(aNotification)
	
}

- (void) applicationDidFinishLaunching:(NSNotification *)aNotification
{

#pragma unused(aNotification)
	
	// Seed the random number generator
	srandom(time(NULL));
	
	// Set up logging
	NSString *appName = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleName"];
	NSString *shortVersionNumber = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleShortVersionString"];
	NSString *versionNumber = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleVersion"];	

	[[Logger sharedLogger] logMessage:@"%@ %@ (%@) log opened", appName, shortVersionNumber, versionNumber];
	
	// Register our URL handlers
	[[NSAppleEventManager sharedAppleEventManager] setEventHandler:self 
													   andSelector:@selector(handleGetURLAppleEvent:withReplyEvent:) 
													 forEventClass:kInternetEventClass 
														andEventID:kAEGetURL];
	
	// Build the "Lookup Metadata Using" menu so it includes all the loaded MusicDatabases
	NSMenu *lookupMetadataUsingMenu = [[NSMenu alloc] initWithTitle:@"Lookup Metadata Using Menu"];
	NSMenu *submitMetadataUsingMenu = [[NSMenu alloc] initWithTitle:@"Submit Metadata Using Menu"];
	
	MusicDatabaseManager *musicDatabaseManager = [MusicDatabaseManager sharedMusicDatabaseManager];
	for(NSBundle *musicDatabaseBundle in musicDatabaseManager.availableMusicDatabases) {
		id <MusicDatabaseInterface> musicDatabaseInterface = [[[musicDatabaseBundle principalClass] alloc] init];

		MusicDatabaseQueryOperation *queryOperation = [musicDatabaseInterface musicDatabaseQueryOperation];
		if(queryOperation) {
			NSMenuItem *menuItem = [[NSMenuItem alloc] initWithTitle:[musicDatabaseBundle objectForInfoDictionaryKey:@"MusicDatabaseName"]
															  action:@selector(queryMusicDatabase:)
													   keyEquivalent:@""];
			
			[menuItem setRepresentedObject:musicDatabaseBundle];			
			[lookupMetadataUsingMenu addItem:menuItem];
		}
		
		MusicDatabaseSubmissionOperation *submissionOperation = [musicDatabaseInterface musicDatabaseSubmissionOperation];
		if(submissionOperation) {
			NSMenuItem *menuItem = [[NSMenuItem alloc] initWithTitle:[musicDatabaseBundle objectForInfoDictionaryKey:@"MusicDatabaseName"]
															  action:@selector(submitToMusicDatabase:)
													   keyEquivalent:@""];
			
			[menuItem setRepresentedObject:musicDatabaseBundle];			
			[submitMetadataUsingMenu addItem:menuItem];
		}
	}
	
	// Add the menu
	NSMenuItem *compactDiscMenuItem = [[[NSApplication sharedApplication] mainMenu] itemAtIndex:3];
	NSMenu *compactDiscMenuItemSubmenu = [compactDiscMenuItem submenu];
	NSMenuItem *lookupTagsUsingMenuItem = [compactDiscMenuItemSubmenu itemWithTag:1];
	NSMenuItem *submitTagsUsingMenuItem = [compactDiscMenuItemSubmenu itemWithTag:2];
	[lookupTagsUsingMenuItem setSubmenu:lookupMetadataUsingMenu];
	[submitTagsUsingMenuItem setSubmenu:submitMetadataUsingMenu];
	
	// Use DiskArbitration to request mount/unmount information for audio CDs
	// Create a dictionary which will match IOMedia objects of type kIOCDMediaClass
	CFMutableDictionaryRef matchDictionary = CFDictionaryCreateMutable(kCFAllocatorDefault, 0, &kCFCopyStringDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
	if(NULL == matchDictionary) {
		NSLog(@"Unable to create a CFMutableDictionaryRef for kIOCDMediaClass matching");
		
		return;
	}
	
	CFDictionarySetValue(matchDictionary, kDADiskDescriptionMediaKindKey, CFSTR(kIOCDMediaClass));
	CFDictionarySetValue(matchDictionary, kDADiskDescriptionMediaWholeKey, kCFBooleanTrue);
	
	// Create a DiskArbitration session in the current run loop
	_diskArbitrationSession = DASessionCreate(kCFAllocatorDefault);
	DASessionScheduleWithRunLoop(_diskArbitrationSession, CFRunLoopGetCurrent(), kCFRunLoopDefaultMode);
	
	// Register our disk appeared and disappeared callbacks
	DARegisterDiskAppearedCallback(_diskArbitrationSession, matchDictionary, diskAppearedCallback, self);
	DARegisterDiskDisappearedCallback(_diskArbitrationSession, matchDictionary, diskDisappearedCallback, self);
	
	CFRelease(matchDictionary);
}

- (NSApplicationTerminateReply) applicationShouldTerminate:(NSApplication *)sender
{
	
#pragma unused(sender)
	
	NSApplicationTerminateReply reply = NSTerminateNow;

	// Don't automatically cancel all encoding operations
	if(0 != [[[[EncoderManager sharedEncoderManager] queue] operations] count]) {
		NSInteger alertReturn = NSRunAlertPanel(NSLocalizedString(@"Encoding is in progress", @""), 
												NSLocalizedString(@"Quitting now may result in incomplete files. Quit anyway?", @""), 
												NSLocalizedString(@"Quit", @"Button"), 
												NSLocalizedString(@"Cancel", @"Button"), 
												nil);
		if(NSAlertAlternateReturn == alertReturn)
			reply = NSTerminateCancel;
	}
	
	if(nil != self.managedObjectContext) {
		if([self.managedObjectContext commitEditing]) {
			NSError *error = nil;
			if(self.managedObjectContext.hasChanges && ![self.managedObjectContext save:&error]) {
				BOOL errorResult = [[NSApplication sharedApplication] presentError:error];

				if(errorResult)
					reply = NSTerminateCancel;
				else {
					NSInteger alertReturn = NSRunAlertPanel(nil, 
															NSLocalizedString(@"Could not save changes while quitting. Quit anyway?", @""), 
															NSLocalizedString(@"Quit", @"Button"), 
															NSLocalizedString(@"Cancel", @"Button"), 
															nil);
					if(NSAlertAlternateReturn == alertReturn)
						reply = NSTerminateCancel;	
				}
			}
		}
		else
			reply = NSTerminateCancel;
	}

	return reply;
}

- (void) applicationWillTerminate:(NSNotification *)aNotification
{
	
#pragma unused(aNotification)
	
	// Stop any encoding operations
	[[[EncoderManager sharedEncoderManager] queue] cancelAllOperations];

	if(_diskArbitrationSession) {
		// Unregister our disk appeared and disappeared callbacks
		DAUnregisterCallback(_diskArbitrationSession, diskAppearedCallback, self);
		DAUnregisterCallback(_diskArbitrationSession, diskDisappearedCallback, self);
		
		// Unschedule and dispose of the DiskArbitration session created for this run loop
		DASessionUnscheduleFromRunLoop(_diskArbitrationSession, CFRunLoopGetCurrent(), kCFRunLoopDefaultMode);
		CFRelease(_diskArbitrationSession), _diskArbitrationSession = NULL;
	}
	
	// Close the log file
	[[Logger sharedLogger] logMessage:NSLocalizedString(@"Log closed", @"")];
	if(_logFile)
		[_logFile closeFile], _logFile = nil;
}

- (BOOL) application:(NSApplication *)theApplication openFile:(NSString *)filename
{

#pragma unused(theApplication)
	
	NSParameterAssert(nil != filename);

//	CFStringRef myUTI = UTTypeCreatePreferredIdentifierForTag(kUTTagClassFilenameExtension, (CFStringRef)pathExtension, kUTTypePlainText);

	return NO;
}

- (NSURL *) applicationSupportFolderURL
{
	NSArray *applicationSupportPaths = NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES);
	NSString *applicationSupportPath = (0 < applicationSupportPaths.count) ? [applicationSupportPaths objectAtIndex:0] : NSTemporaryDirectory();
	NSString *applicationName = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleName"];
	NSString *applicationSupportFolder = [applicationSupportPath stringByAppendingPathComponent:applicationName];
	
	return [NSURL fileURLWithPath:applicationSupportFolder];
}

- (NSURL *) applicationLogFileURL
{
	NSArray *userLibraryPaths = NSSearchPathForDirectoriesInDomains(NSLibraryDirectory, NSUserDomainMask, YES);
	NSString *userLibraryPath = (0 < userLibraryPaths.count) ? [userLibraryPaths objectAtIndex:0] : NSTemporaryDirectory();
	NSString *userLogsPath = [userLibraryPath stringByAppendingPathComponent:@"Logs"];
	NSString *applicationName = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleName"];
	NSString *logFileName = [applicationName stringByAppendingPathExtension:@"log"];
	NSString *applicationLogPath = [userLogsPath stringByAppendingPathComponent:logFileName];
	
	return [NSURL fileURLWithPath:applicationLogPath];
}

#pragma mark Standard Core Data

- (NSManagedObjectModel *) managedObjectModel
{
	if(!_managedObjectModel)
		self.managedObjectModel = [NSManagedObjectModel mergedModelFromBundles:nil];

	return _managedObjectModel;
}

- (NSPersistentStoreCoordinator *) persistentStoreCoordinator
{
	if(nil != _persistentStoreCoordinator)
		return _persistentStoreCoordinator;

	NSFileManager *fileManager = [NSFileManager defaultManager];
	NSString *applicationSupportFolderPath = self.applicationSupportFolderURL.path;
	
	NSError *error = nil;

	// Create the Application Support directory if it doesn't exist
	if(![fileManager fileExistsAtPath:applicationSupportFolderPath isDirectory:NULL] && ![fileManager createDirectoryAtPath:applicationSupportFolderPath withIntermediateDirectories:YES attributes:nil error:&error])
		[[NSApplication sharedApplication] presentError:error];

	NSURL *url = [NSURL fileURLWithPath:[applicationSupportFolderPath stringByAppendingPathComponent:@"Ripped CDs.sqlite"]];

	self.persistentStoreCoordinator = [[NSPersistentStoreCoordinator alloc] initWithManagedObjectModel:self.managedObjectModel];

	// Add the main store
	self.primaryStore = [_persistentStoreCoordinator addPersistentStoreWithType:NSSQLiteStoreType configuration:nil URL:url options:nil error:&error];
	if(!self.primaryStore)
		[[NSApplication sharedApplication] presentError:error];

	// Add an in-memory store as a temporary home
	self.inMemoryStore = [_persistentStoreCoordinator addPersistentStoreWithType:NSInMemoryStoreType configuration:nil URL:nil options:nil error:&error];
	if(!self.inMemoryStore)
		[[NSApplication sharedApplication] presentError:error];

	return _persistentStoreCoordinator;
}

- (NSManagedObjectContext *) managedObjectContext
{
	if(nil != _managedObjectContext)
		return _managedObjectContext;

	NSPersistentStoreCoordinator *coordinator = self.persistentStoreCoordinator;
	if(nil != coordinator) {
		self.managedObjectContext = [[NSManagedObjectContext alloc] init];
		[_managedObjectContext setPersistentStoreCoordinator:coordinator];
	}

	return _managedObjectContext;
}

#pragma mark Action methods

- (IBAction) saveAction:(id)sender
{

#pragma unused(sender)

	if(!self.managedObjectContext.hasChanges)
		return;
	
	NSError *error = nil;
	if(![self.managedObjectContext save:&error])
		[[NSApplication sharedApplication] presentError:error];
}

@end

@implementation ApplicationDelegate (Private)

- (void) diskAppeared:(DADiskRef)disk
{
	NSParameterAssert(NULL != disk);

	[[Logger sharedLogger] logMessageWithLevel:eLogMessageLevelDebug format:NSLocalizedString(@"Found compact disc on %s", @""), DADiskGetBSDName(disk)];
	
	// Create a new window for this disk
	CompactDiscWindowController *compactDiscWindow = [[CompactDiscWindowController alloc] init];
	compactDiscWindow.disk = disk;

	// If this is the first time this disc has been seen, query AccurateRip and/or a music database
	if([compactDiscWindow.compactDisc isInserted]) {

		// Actions such as querying AccurateRip pass objectIDs across threads, so the managed object context
		// must be saved before any queries are performed
		[self saveAction:self];
		
		[compactDiscWindow showWindow:self];
		
		if([[NSUserDefaults standardUserDefaults] boolForKey:@"automaticallyQueryAccurateRip"])
			[compactDiscWindow queryAccurateRip:self];
		
		if([[NSUserDefaults standardUserDefaults] boolForKey:@"automaticallyQueryMusicDatabase"])
			[compactDiscWindow queryDefaultMusicDatabase:self];
		
		// Automatically select all the tracks
		[compactDiscWindow selectAllTracks:self];
	}
	else
		[compactDiscWindow showWindow:self];

	// If the read offset for the drive isn't configured, give the user the opportunity to configure it now
	if(!compactDiscWindow.driveInformation.readOffset && [compactDiscWindow.compactDisc.accurateRipDiscs count]) {
		// Check and see if this drive has a known read offset
		NSString *driveOffsetsPath = [[NSBundle mainBundle] pathForResource:@"DriveOffsets" ofType:@"plist" inDirectory:nil];
		NSDictionary *driveOffsets = [NSDictionary dictionaryWithContentsOfFile:driveOffsetsPath];

		NSNumber *driveOffset = [driveOffsets objectForKey:compactDiscWindow.driveInformation.productName];
		if(driveOffset)
			NSBeginAlertSheet([NSString stringWithFormat:NSLocalizedString(@"The suggested read offset for \u201c%@ %@\u201d is %@ audio frames.  Would you like to use this read offset?", @""), compactDiscWindow.driveInformation.vendorName, compactDiscWindow.driveInformation.productName, driveOffset],
							  NSLocalizedString(@"Yes", @""), 
							  NSLocalizedString(@"Calculate", @""),
							  NSLocalizedString(@"No", @""),
							  compactDiscWindow.window,
							  self,
							  @selector(readOffsetKnownSheetDidEnd:returnCode:contextInfo:),
							  NULL,
							  [NSArray arrayWithObjects:compactDiscWindow, driveOffset, nil], 
							  NSLocalizedString(@"Configuring a read offset will allow more accurate audio extraction by enabling use of the AccurateRip database.", @""));
		else
			NSBeginAlertSheet([NSString stringWithFormat:NSLocalizedString(@"The read offset for \u201c%@ %@\u201d is unknown.  Would you like to determine the drive's read offset now?", @""), compactDiscWindow.driveInformation.vendorName, compactDiscWindow.driveInformation.productName],
							  NSLocalizedString(@"Yes", @""), 
							  NSLocalizedString(@"No", @""),
							  nil,
							  compactDiscWindow.window,
							  self,
							  @selector(readOffsetNotConfiguredSheetDidEnd:returnCode:contextInfo:),
							  NULL,
							  compactDiscWindow, 
							  NSLocalizedString(@"Configuring a read offset will allow more accurate audio extraction by enabling use of the AccurateRip database.", @""));
	}
}

- (void) diskDisappeared:(DADiskRef)disk
{
	NSParameterAssert(NULL != disk);

	CompactDiscWindowController *matchingWindowController = nil;
	
	// Iterate through open windows and determine which one matches this disk
	for(NSWindow *window in [[NSApplication sharedApplication] windows]) {
		NSWindowController *windowController = window.windowController;
		if(windowController && [windowController isKindOfClass:[CompactDiscWindowController class]] && CFEqual(((CompactDiscWindowController *)windowController).disk, disk)) {
			matchingWindowController = (CompactDiscWindowController *)windowController;
			break;
		}
	}
	
	// Set the disk to NULL, to allow the window's resources to be garbage collected
	if(matchingWindowController) {
		matchingWindowController.disk = NULL;
		[matchingWindowController close];
	}
}

- (void) handleGetURLAppleEvent:(NSAppleEventDescriptor *)event withReplyEvent:(NSAppleEventDescriptor *)replyEvent
{
	
#pragma unused(replyEvent)
	
	NSURL *url = [NSURL URLWithString:[[event paramDescriptorForKeyword:keyDirectObject] stringValue]];
}

- (void) readOffsetKnownSheetDidEnd:(NSWindow *)sheet returnCode:(NSInteger)returnCode contextInfo:(void *)contextInfo
{	
	NSParameterAssert(NULL != contextInfo);
	
	[sheet orderOut:self];
	
	// Default is YES, other is NO, alternate is CALCULATE
	if(NSAlertOtherReturn == returnCode)
		return;
	
	NSArray *parameters = (NSArray *)contextInfo;
	CompactDiscWindowController *compactDiscWindowController = [parameters objectAtIndex:0];
	NSNumber *readOffset = [parameters objectAtIndex:1];
	
	if(NSAlertDefaultReturn == returnCode)
		compactDiscWindowController.driveInformation.readOffset = readOffset;
	else
		[compactDiscWindowController determineDriveReadOffset:self];
}

- (void) readOffsetNotConfiguredSheetDidEnd:(NSWindow *)sheet returnCode:(NSInteger)returnCode contextInfo:(void *)contextInfo
{	
	NSParameterAssert(NULL != contextInfo);
	
	[sheet orderOut:self];
	
	// Default is YES, alternate is NO
	if(NSAlertAlternateReturn == returnCode)
		return;
	
	CompactDiscWindowController *compactDiscWindowController = (CompactDiscWindowController *)contextInfo;
	
	[compactDiscWindowController determineDriveReadOffset:self];
}

@end
