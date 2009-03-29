/*
 *  Copyright (C) 2009 Stephen F. Booth <me@sbooth.org>
 *  All Rights Reserved
 */

#import "ETAFormatter.h"

#include <math.h>

#define SECONDS_PER_MINUTE 60.0
#define MINUTES_PER_HOUR 60.0

@implementation ETAFormatter

@synthesize includeSeconds = _includeSeconds;

- (id) init
{
	if((self = [super init]))
		self.includeSeconds = YES;
	return self;
}

- (NSString *) stringForObjectValue:(id)anObject
{
	if(!anObject || ![anObject respondsToSelector:@selector(doubleValue)])
		return nil;
	
	NSTimeInterval interval = [anObject doubleValue];
	
	NSTimeInterval intervalInSeconds = fabs(interval);
	double intervalInMinutes = round(intervalInSeconds / SECONDS_PER_MINUTE);
	
	if(intervalInMinutes >= 0 && intervalInMinutes <= 1) {
		if(!self.includeSeconds)
			return (intervalInMinutes == 0 ? @"less than a minute" : @"1 minute");
		if(intervalInSeconds >= 0 && intervalInSeconds <= 4)
			return @"less than 5 seconds";
		else if(intervalInSeconds >= 5 && intervalInSeconds <= 9) 
			return @"less than 10 seconds";
		else if(intervalInSeconds >= 10 && intervalInSeconds <= 19) 
			return @"less than 20 seconds";
		else if(intervalInSeconds >= 20 && intervalInSeconds <= 39) 
			return @"half a minute";
		else if(intervalInSeconds >= 40 && intervalInSeconds <= 59) 
			return @"less than a minute";
		else 
			return @"1 minute";
	}
	else if(intervalInMinutes >= 2 && intervalInMinutes <= 44) 
		return [NSString stringWithFormat:@"%.0f minutes", intervalInMinutes];
	else if(intervalInMinutes >= 45 && intervalInMinutes <= 89) 
		return @"about 1 hour";
	else if(intervalInMinutes >= 90 && intervalInMinutes <= 1439) 
		return [NSString stringWithFormat:@"about %.0f hours", round(intervalInMinutes / MINUTES_PER_HOUR)];
	else if(intervalInMinutes >= 1440 && intervalInMinutes <= 2879) 
		return @"1 day";
	else if(intervalInMinutes >= 2880 && intervalInMinutes <= 43199) 
		return [NSString stringWithFormat:@"%.0f days", round(intervalInMinutes / 1440.0)];
	else if(intervalInMinutes >= 43200 && intervalInMinutes <= 86399) 
		return @"about 1 month";
	else if(intervalInMinutes >= 86400 && intervalInMinutes <= 525599) 
		return [NSString stringWithFormat:@"%.0f months", round(intervalInMinutes / 43200.0)];
	else if(intervalInMinutes >= 525600 && intervalInMinutes <= 1051199) 
		return @"about 1 year";
	else
		return [NSString stringWithFormat:@"over %.0f years", round(intervalInMinutes / 525600.0)];
}

- (NSAttributedString *) attributedStringForObjectValue:(id)object withDefaultAttributes:(NSDictionary *)attributes
{
	return [[NSAttributedString alloc] initWithString:[self stringForObjectValue:object] attributes:attributes];
}

@end
