/*
 *  Copyright (C) 2007 - 2009 Stephen F. Booth <me@sbooth.org>
 *  All Rights Reserved
 */

#import "ApplicationDelegate.h"
#import "CompactDiscWindowController.h"
#import "CompactDisc.h"
#import "DriveInformation.h"
#import "EncoderManager.h"
#import "MusicDatabaseManager.h"
#import "MetadataSourceManager.h"
#import "ReadOffsetCalculatorSheetController.h"
#import "Logger.h"

#import "AquaticPrime.h"

#import "ByteSizeValueTransformer.h"
#import "DurationValueTransformer.h"

#import "MusicDatabaseInterface/MusicDatabaseInterface.h"
#import "MusicDatabaseInterface/MusicDatabaseQueryOperation.h"
#import "MusicDatabaseInterface/MusicDatabaseSubmissionOperation.h"

#import "MetadataSourceInterface/MetadataSourceInterface.h"

#import <SFBCrashReporter/SFBCrashReporter.h>

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
- (NSURL *) locateLicenseURL;
- (BOOL) validateLicenseURL:(NSURL *)licenseURL error:(NSError **)error;
- (void) displayNagDialog;
- (void) handleGetURLAppleEvent:(NSAppleEventDescriptor *)event withReplyEvent:(NSAppleEventDescriptor *)replyEvent;
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
	[defaultsDictionary setObject:[NSNumber numberWithInteger:2] forKey:@"requiredSectorMatches"];
	[defaultsDictionary setObject:[NSNumber numberWithInteger:1] forKey:@"requiredTrackMatches"];
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
	
#if ENABLE_LICENSING_CODE
	// Determine if this application is registered, and if not, display a nag dialog
	NSURL *licenseURL = [self locateLicenseURL];
	if(licenseURL) {
		NSError *error = nil;
		if(![self validateLicenseURL:licenseURL error:&error]) {
			[[NSApplication sharedApplication] presentError:error];
			[[NSApplication sharedApplication] terminate:self];
		}
	}
	else
		[self displayNagDialog];
#endif

	// Check for and send crash reports
	[SFBCrashReporter checkForNewCrashes];
	
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
	
	// Build the "Search For Metadata Using" menu so it includes all the loaded MetadataSources
	NSMenu *searchForMetadataUsingMenu = [[NSMenu alloc] initWithTitle:@"Search For Metadata Using Menu"];
	
	MetadataSourceManager *metadataSourceManager = [MetadataSourceManager sharedMetadataSourceManager];
	for(NSBundle *metadataSourceBundle in metadataSourceManager.availableMetadataSources) {
		id <MetadataSourceInterface> metadataSourceInterface = [[[metadataSourceBundle principalClass] alloc] init];
		
		if(metadataSourceInterface) {
			NSMenuItem *menuItem = [[NSMenuItem alloc] initWithTitle:[metadataSourceBundle objectForInfoDictionaryKey:@"MetadataSourceName"]
															  action:@selector(searchForMetadata:)
													   keyEquivalent:@""];
			
			[menuItem setRepresentedObject:metadataSourceBundle];			
			[searchForMetadataUsingMenu addItem:menuItem];
		}
	}
	
	// Add the menu
	NSMenuItem *searchForMetadataUsingMenuItem = [compactDiscMenuItemSubmenu itemWithTag:3];
	[searchForMetadataUsingMenuItem setSubmenu:searchForMetadataUsingMenu];
	
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
	
	// Re-open windows
	if([[NSUserDefaults standardUserDefaults] boolForKey:@"Inspector Panel Open"])
		[_inspectorPanelWindowController showWindow:self];

	if([[NSUserDefaults standardUserDefaults] boolForKey:@"Metadata Editor Open"])
		[_metadataEditorPanelWindowController showWindow:self];
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
	
	// Save the closed/open state of important windows
	if([_inspectorPanelWindowController isWindowLoaded])
		[[NSUserDefaults standardUserDefaults] setBool:[[_inspectorPanelWindowController window] isVisible] forKey:@"Inspector Panel Open"];

	if([_metadataEditorPanelWindowController isWindowLoaded])
		[[NSUserDefaults standardUserDefaults] setBool:[[_metadataEditorPanelWindowController window] isVisible] forKey:@"Metadata Editor Open"];

	[[NSUserDefaults standardUserDefaults] synchronize];
	
	// Close the log file
	[[Logger sharedLogger] logMessage:NSLocalizedString(@"Log closed", @"")];
	if(_logFile)
		[_logFile closeFile], _logFile = nil;
}

- (BOOL) application:(NSApplication *)theApplication openFile:(NSString *)filename
{
	NSParameterAssert(nil != filename);
	
	NSString *pathExtension = [filename pathExtension];
	
//	CFStringRef myUTI = UTTypeCreatePreferredIdentifierForTag(kUTTagClassFilenameExtension, (CFStringRef)pathExtension, kUTTypePlainText);
	
	if([pathExtension isEqualToString:@"rip-license"]) {
		NSError *error = nil;
		if([self validateLicenseURL:[NSURL fileURLWithPath:filename] error:&error]) {
			NSString *licenseCopyPath = [self.applicationSupportFolderURL.path stringByAppendingPathComponent:filename.lastPathComponent];
			if(![[NSFileManager defaultManager] copyItemAtPath:filename toPath:licenseCopyPath error:&error])
				[theApplication presentError:error];
		}
		else
			[theApplication presentError:error];
		
		return YES;
	}
	else
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
	if(!compactDiscWindow.driveInformation.readOffset)
		[compactDiscWindow determineDriveReadOffset:self];
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

- (NSURL *) locateLicenseURL
{
	// Search for a license file in the Application Support folder
	NSString *applicationSupportFolderPath = self.applicationSupportFolderURL.path;
	NSDirectoryEnumerator *directoryEnumerator = [[NSFileManager defaultManager] enumeratorAtPath:applicationSupportFolderPath];
	
	NSString *path = nil;
	while((path = [directoryEnumerator nextObject])) {
		// Just return the first one found
		if([path.pathExtension isEqualToString:@"rip-license"])
			return [NSURL fileURLWithPath:[applicationSupportFolderPath stringByAppendingPathComponent:path]];			
	}
	
	return nil;
}

- (BOOL) validateLicenseURL:(NSURL *)licenseURL error:(NSError **)error
{
	NSParameterAssert(nil != licenseURL);
	
	// This string is specially constructed to prevent key replacement
	NSMutableString *publicKey = [NSMutableString string];
	[publicKey appendString:@"0xB41079DB7"];
	[publicKey appendString:@"B"];
	[publicKey appendString:@"B"];
	[publicKey appendString:@"B3FA82DEFD95ABC7E"];
	[publicKey appendString:@"D923F96C0C"];
	[publicKey appendString:@"2"];
	[publicKey appendString:@"2"];
	[publicKey appendString:@"174947E10FAC0BAD48"];
	[publicKey appendString:@"4"];
	[publicKey appendString:@"E"];
	[publicKey appendString:@"E"];
	[publicKey appendString:@"37F5672F71C0D5DE95B9D8BECE2"];
	[publicKey appendString:@"6D4A2076E149E4C35"];
	[publicKey appendString:@"0"];
	[publicKey appendString:@"0"];
	[publicKey appendString:@"16662D0E41D"];
	[publicKey appendString:@"6231FB7ED6E9"];
	[publicKey appendString:@"5"];
	[publicKey appendString:@"5"];
	[publicKey appendString:@"A56E975ECCB6566E"];
	[publicKey appendString:@"4C701DEA7A62B620878E1B534C19B4"];
	[publicKey appendString:@"9C9A95D9E52"];
	[publicKey appendString:@"3"];
	[publicKey appendString:@"3"];
	[publicKey appendString:@"1D8708BA81E325AB6"];
	[publicKey appendString:@"54F"];
	[publicKey appendString:@"C"];
	[publicKey appendString:@"C"];
	[publicKey appendString:@"89B2FF1CC1026247D6B2BB1C3"];
	[publicKey appendString:@"DCC8564BED5E2E46F1"];
	
	AquaticPrime *licenseValidator = [AquaticPrime aquaticPrimeWithKey:publicKey];
	NSDictionary *licenseDictionary = [licenseValidator dictionaryForLicenseURL:licenseURL];
	
	// This is an invalid license
	if(!licenseDictionary) {
		if(error) {
			NSMutableDictionary *userInfo = [NSMutableDictionary dictionary];
			[userInfo setObject:licenseURL.path forKey:NSFilePathErrorKey];
			[userInfo setObject:NSLocalizedString(@"Your license is invalid or corrupted.", @"") forKey:NSLocalizedDescriptionKey];
			[userInfo setObject:NSLocalizedString(@"The license file could be incomplete or might contain an invalid key.", @"") forKey:NSLocalizedRecoverySuggestionErrorKey];
			
			*error = [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileReadCorruptFileError userInfo:userInfo];
		}
		
		return NO;		
	}
	
	// TODO: Make sure the license is sane
	return YES;
}

- (void) displayNagDialog
{
	// Create the nag dialog
	NSPanel *panel = NSGetAlertPanel(NSLocalizedString(@"This copy of Rip is unregistered.", @""),
									 NSLocalizedString(@"You may purchase a license at http://sbooth.org/Rip/.", @""),
									 NSLocalizedString(@"OK", @"Button"),
									 nil,
									 nil);
	
	// Locate the OK button
	NSButton *okButton = nil;
	for(NSView *view in [[panel contentView] subviews]) {
		if([view isKindOfClass:[NSButton class]] && [[(NSButton *)view title] isEqualToString:NSLocalizedString(@"OK", @"Button")]) {
			okButton = (NSButton *)view;
			break;
		}
	}
	
	// Sanity check
	if(!okButton)
		NSLog(@"fnord");
	
	// And disable it
	[okButton setEnabled:NO];
	
	// Display the nag dialog for 5 seconds
	NSDate *stopTime = [NSDate dateWithTimeIntervalSinceNow:5.0];
	
	// Run the window in a modal session, to prevent any background events from posting
	NSModalSession session = [[NSApplication sharedApplication] beginModalSessionForWindow:panel];
	for(;;) {
		// Stop the modal session as required
		if(NSRunContinuesResponse != [[NSApplication sharedApplication] runModalSession:session])
			break;
		
		// Check and see if the time is up; if so, enable the OK button
		if(0 > [stopTime timeIntervalSinceNow])
			[okButton setEnabled:YES];
	}
	[[NSApplication sharedApplication] endModalSession:session];
	
	[panel orderOut:self];
		
	NSReleaseAlertPanel(panel);	
}

- (void) handleGetURLAppleEvent:(NSAppleEventDescriptor *)event withReplyEvent:(NSAppleEventDescriptor *)replyEvent
{
	
#pragma unused(replyEvent)
	
	NSURL *url = [NSURL URLWithString:[[event paramDescriptorForKeyword:keyDirectObject] stringValue]];
	NSLog(@"%@", url);
}

@end
