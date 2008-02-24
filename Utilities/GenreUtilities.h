/*
 *  Copyright (C) 2006 - 2008 Stephen F. Booth <me@sbooth.org>
 *  All Rights Reserved
 */

#pragma once

#import <Cocoa/Cocoa.h>

// Returns an array containing the ID3v1 genres and WinAmp extensions
NSArray * genres(void);

// Returns an alphabetically sorted array containing the ID3v1 genres and WinAmp extensions
NSArray * sortedGenres(void);
