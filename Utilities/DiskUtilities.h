/*
 *  Copyright (C) 2005 - 2009 Stephen F. Booth <me@sbooth.org>
 *  All Rights Reserved
 */

#pragma once

#import <Cocoa/Cocoa.h>
#import <DiskArbitration/DiskArbitration.h>

// ========================================
// Utility function that extracts the device identifier from a DADiskRef
// ========================================
NSString * getDeviceIdentifierForDADiskRef(DADiskRef disk);

// ========================================
// Utility function that extracts the device properties for a drive via a DADiskRef
// ========================================
NSDictionary * getDevicePropertiesForDADiskRef(DADiskRef disk);
