/*
 *  Copyright (C) 2008 Stephen F. Booth <me@sbooth.org>
 *  All Rights Reserved
 */

#import "Logger.h"
#import "ApplicationDelegate.h"

// ========================================
// Private methods
// ========================================
@interface Logger (Private)
- (BOOL) openLogFile;
- (void) closeLogFile;
- (void) logMessage:(NSString *)message level:(eLogMessageLevel)level;
@end

// ========================================
// Static variables
// ========================================
static Logger *sSharedLogger				= nil;

@implementation Logger

@synthesize logMessageLevel = _logMessageLevel;

+ (id) sharedLogger
{
	if(!sSharedLogger)
		sSharedLogger = [[self alloc] init];
	return sSharedLogger;
}

- (id) init
{
	if((self = [super init])) {
		self.logMessageLevel = [[NSUserDefaults standardUserDefaults] integerForKey:@"logMessageLevel"];
		if(![self openLogFile])
			return nil;
	}
	return self;
}

- (void) logMessage:(NSString *)format, ...
{
	NSParameterAssert(nil != format);
	
	va_list ap;
	
	va_start(ap, format);
	
	NSString *message = [[NSString alloc] initWithFormat:format arguments:ap];
	[self logMessage:message level:eLogMessageLevelNormal];
	
	va_end(ap);
}

- (void) logMessageWithLevel:(eLogMessageLevel)level format:(NSString *)format, ...
{
	NSParameterAssert(nil != format);
	
	va_list ap;
	
	va_start(ap, format);
	
	NSString *message = [[NSString alloc] initWithFormat:format arguments:ap];
	[self logMessage:message level:level];
	
	va_end(ap);
}

@end

@implementation Logger (Private)

- (BOOL) openLogFile
{
	// File already open
	if(_logFile)
		return YES;

	// Open the log file
	NSString *logFilePath = [[(ApplicationDelegate *)[[NSApplication sharedApplication] delegate] applicationLogFileURL] path];
	
	// Create the file if it doesn't exist
	if(![[NSFileManager defaultManager] fileExistsAtPath:logFilePath]) {
		if(![[NSFileManager defaultManager] createFileAtPath:logFilePath contents:nil attributes:nil]) {
			NSLog(@"Unable to create a log file at %@", logFilePath);
			return NO;
		}
	}
	
	_logFile = [NSFileHandle fileHandleForWritingAtPath:logFilePath];
	[_logFile seekToEndOfFile];
	
	return YES;
}

- (void) closeLogFile
{
	if(_logFile)
		[_logFile closeFile], _logFile = nil;
}

- (void) logMessage:(NSString *)message level:(eLogMessageLevel)level
{
	NSParameterAssert(nil != message);
	
#if DEBUG
	NSLog(message);
#endif
	
	// Only log messages with the specified log level or less
	if(self.logMessageLevel < level)
		return;
	
	// Add a timestamp
	NSMutableString *logMessage = [NSMutableString string];
	[logMessage appendFormat:@"[%@] %@\n", [NSDate date], message];
	
	// Use UTF-8 for the file's data
	NSData *data = [logMessage dataUsingEncoding:NSUTF8StringEncoding];
	
	// Don't let an exception here ruin our day
	@try {
		[_logFile writeData:data];
	}
	@catch(NSException *exception) {
		NSLog(@"Unable to write to log file: %@", exception);
	}
}

@end
