/*
 *  Copyright (C) 2008 Stephen F. Booth <me@sbooth.org>
 *  All Rights Reserved
 */

#import <Cocoa/Cocoa.h>

// ========================================
// Enum for user defaults output file handling
// ========================================
enum _eLogMessageLevel {
	eLogMessageLevelSilent = 0,
	eLogMessageLevelNormal = 1,
	eLogMessageLevelDebug = 2,
	eLogMessageLevelFull = 3
};
typedef enum _eLogMessageLevel eLogMessageLevel;

// ========================================
// Class for logging messages to the application's log file
// ========================================
@interface Logger : NSObject
{
@private
	NSFileHandle *_logFile;
	eLogMessageLevel _logMessageLevel;
}

// ========================================
// The shared instance
+ (id) sharedLogger;

// ========================================
// Properties
@property (assign) eLogMessageLevel logMessageLevel;

// ========================================
// Logging
- (void) logMessage:(NSString *)format, ...;
- (void) logMessageWithLevel:(eLogMessageLevel)level format:(NSString *)format, ...;

@end
