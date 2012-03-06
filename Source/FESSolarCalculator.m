//
//  FESSolarCalculator.m
//  SolarCalculatorExample
//
//  Created by Dan Weeks on 2012-02-11.
//  Copyright © 2012 Daniel Weeks.
//  
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the “Software”), to deal
//  in the Software without restriction, including without limitation the rights
//  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//  
//  The above copyright notice and this permission notice shall be included in
//  all copies or substantial portions of the Software.
//  
//  THE SOFTWARE IS PROVIDED “AS IS”, WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
//  THE SOFTWARE.
//

// math source: http://williams.best.vwh.net/sunrise_sunset_algorithm.htm

#if ! __has_feature(objc_arc)
#error This file must be compiled with ARC.
#endif

#import "FESSolarCalculator.h"
#include "math.h"
#include "tgmath.h"


//#if defined(FESSOLARCALCULATOR_DEBUG) && (FESSOLARCALCULATOR_DEBUG == 1)
#if defined(DEBUG) && (DEBUG == 1)
    #define dNSLog( a, var_args1... ) NSLog( a, ## var_args1 )
    #define dElseNSLog( a, var_args1...) else NSLog( a, ## var_args1 )
#else
    #define dNSLog( a, var_args...)
    #define dElseNSLog( a, var_args1...)
#endif

double const FESSolarCalculationZenithOfficial = 90.8333;
double const FESSolarCalculationZenithCivil = 96.0;
double const FESSolarCalculationZenithNautical = 102.0;
double const FESSolarCalculationZenithAstronomical = 108.0;

double const toRadians = M_PI / 180;
double const toDegrees = 180 / M_PI;

@interface FESSolarCalculator ( )

@property (nonatomic, readwrite, strong) NSDate *sunrise;
@property (nonatomic, readwrite, strong) NSDate *sunset;
@property (nonatomic, readwrite, strong) NSDate *solarNoon;
@property (nonatomic, readwrite, strong) NSDate *civilDawn;
@property (nonatomic, readwrite, strong) NSDate *civilDusk;
@property (nonatomic, readwrite, strong) NSDate *nauticalDawn;
@property (nonatomic, readwrite, strong) NSDate *nauticalDusk;
@property (nonatomic, readwrite, strong) NSDate *astronomicalDawn;
@property (nonatomic, readwrite, strong) NSDate *astronomicalDusk;

- (void)invalidateResults;

@end

@implementation FESSolarCalculator

@synthesize operationsMask=_operationsMask;
@synthesize startDate=_startDate;
@synthesize location=_location;
@synthesize sunrise=_sunrise;
@synthesize sunset=_sunset;
@synthesize solarNoon=_solarNoon;
@synthesize civilDawn=_civilDawn;
@synthesize civilDusk=_civilDusk;
@synthesize nauticalDawn=_nauticalDawn;
@synthesize nauticalDusk=_nauticalDusk;
@synthesize astronomicalDawn=_astronomicalDawn;
@synthesize astronomicalDusk=_astronomicalDusk;

#pragma mark -
#pragma mark Initializers


- (id)init
{
    self = [super init];
    if (self) {
        // set our default operations mask
        _operationsMask = FESSolarCalculationAll;
        [self invalidateResults];
    }
    return self;
}

- (id)initWithDate:(NSDate *)inDate location:(CLLocation *)inLocation
{
    self = [self init];
    if (self) {
        [self setStartDate:inDate];
        [self setLocation:inLocation];
    }
    return self;
}

- (id)initWithDate:(NSDate *)inDate location:(CLLocation *)inLocation mask:(FESSolarCalculationType)inMask
{
    self = [self initWithDate:inDate location:inLocation];
    if (self) {
        [self setOperationsMask:inMask];
    }
    return self;
}

#pragma mark -
#pragma mark Property Ops

- (void)setStartDate:(NSDate *)inDate
{
    // override the default setter for startDate so that we can invalidate previous results
    [self invalidateResults];
    _startDate = inDate;
}

- (void)setLocation:(CLLocation *)inLocation
{
    // override the default setter for location so that we can invalidate previous results
    [self invalidateResults];
    _location = inLocation;
}

- (void)invalidateResults
{
    // when users set new inputs the output values need to be invalidated
    _sunrise = nil;
    _sunset = nil;
    _solarNoon = nil;
    _civilDawn = nil;
    _civilDusk = nil;
    _nauticalDawn = nil;
    _nauticalDusk = nil;
    _astronomicalDawn = nil;
    _astronomicalDusk = nil;
}

#pragma mark -
#pragma mark User Facing Methods

- (void)calculate
{
    // run the calculations based on the users criteria
    NSCalendar *gregorian = [[NSCalendar alloc] initWithCalendarIdentifier:NSGregorianCalendar];
    NSUInteger numberDayOfYear = [gregorian ordinalityOfUnit:NSDayCalendarUnit inUnit:NSYearCalendarUnit forDate:self.startDate];
    
    double longitudeHour = [self longitudeHourFromLongitude:self.location.coordinate.longitude];
    double approximateTimeRising = [self approximateTimeFromDayOfYear:numberDayOfYear longitudeHour:longitudeHour direction:FESSolarCalculationRising];
    double approximateTimeSetting = [self approximateTimeFromDayOfYear:numberDayOfYear longitudeHour:longitudeHour direction:FESSolarCalculationSetting];
    double meanAnomolyRising = [self sunsMeanAnomolyFromApproximateTime:approximateTimeRising];
    double meanAnomolySetting = [self sunsMeanAnomolyFromApproximateTime:approximateTimeSetting];
    double trueLongitudeRising = [self sunsTrueLongitudeFromMeanAnomoly:meanAnomolyRising];
    double trueLongitudeSetting = [self sunsTrueLongitudeFromMeanAnomoly:meanAnomolySetting];
    double rightAscensionRising = [self sunsRightAscensionFromTrueLongitude:trueLongitudeRising];
    double rightAscensionSetting = [self sunsRightAscensionFromTrueLongitude:trueLongitudeSetting];
    
    void (^computeSolarData)(FESSolarCalculationType, FESSolarCalculationDirection, double) = ^(FESSolarCalculationType calculationType, FESSolarCalculationDirection direction, double zenith) {
        
        double trueLongitude = trueLongitudeRising;
        double rightAscension = rightAscensionRising;
        double approximateTime = approximateTimeRising;
        if ((direction & FESSolarCalculationSetting) == FESSolarCalculationSetting) {
            trueLongitude = trueLongitudeSetting;
            rightAscension = rightAscensionSetting;
            approximateTime = approximateTimeSetting;
        }
        double localHourAngle = [self sunsLocalHourAngleFromTrueLongitude:trueLongitude latitude:self.location.coordinate.latitude zenith:zenith direction:direction];
        double localMeanTime = [self calculateLocalMeanTimeFromLocalHourAngle:localHourAngle rightAscension:rightAscension approximateTime:approximateTime];
        double timeInUTC = [self convertToUTCFromLocalMeanTime:localMeanTime longitudeHour:longitudeHour];

        NSLog(@"local hour: %f", localHourAngle);
        NSLog(@"time in UTC: %f", timeInUTC);
        NSDateComponents *components = [gregorian components:(NSYearCalendarUnit | NSMonthCalendarUnit | NSDayCalendarUnit | NSHourCalendarUnit | NSMinuteCalendarUnit | NSSecondCalendarUnit) fromDate:self.startDate];
        [components setTimeZone:[NSTimeZone timeZoneWithName:@"GMT"]];
        [components setHour:(int)round(timeInUTC)];
        double minutes = (timeInUTC - round(timeInUTC)) * 60;
        [components setMinute:(int)round(minutes)];
        [components setSecond:(int)((minutes - round(minutes)) * 60)];
        
        NSDate *setDate = [gregorian dateFromComponents:components];
        NSLog(@"start: %@", self.startDate);
        NSLog(@"set: %@", setDate);
        
        if ((calculationType & FESSolarCalculationOfficial) == FESSolarCalculationOfficial) {
            if ((direction & FESSolarCalculationRising) == FESSolarCalculationRising) {
                _sunrise = setDate;
            } else {
                _sunset = setDate;
            }
        } else if ((calculationType & FESSolarCalculationCivil) == FESSolarCalculationCivil) {
            if ((direction & FESSolarCalculationRising) == FESSolarCalculationRising) {
                _civilDawn = setDate;
            } else {
                _civilDusk = setDate;
            }
        } else if ((calculationType & FESSolarCalculationNautical) == FESSolarCalculationNautical) {
            if ((direction & FESSolarCalculationRising) == FESSolarCalculationRising) {
                _nauticalDawn = setDate;
            } else {
                _nauticalDusk = setDate;
            }
        } else if ((calculationType & FESSolarCalculationAstronomical) == FESSolarCalculationAstronomical) {            
            if ((direction & FESSolarCalculationRising) == FESSolarCalculationRising) {
                _astronomicalDawn = setDate;
            } else {
                _astronomicalDusk = setDate;
            }
        }
    };
    
    FESSolarCalculationType theseOps = self.operationsMask;
    if ((self.operationsMask & FESSolarCalculationAll) == FESSolarCalculationAll) {
        theseOps = FESSolarCalculationOfficial | FESSolarCalculationCivil | FESSolarCalculationNautical | FESSolarCalculationAstronomical;
    }
    if ((theseOps & FESSolarCalculationOfficial) == FESSolarCalculationOfficial) {
        computeSolarData(FESSolarCalculationOfficial, FESSolarCalculationRising, FESSolarCalculationZenithOfficial);
        computeSolarData(FESSolarCalculationOfficial, FESSolarCalculationSetting, FESSolarCalculationZenithOfficial);
        NSLog(@"sunrise: %@", self.sunrise);
        NSLog(@"sunset: %@", self.sunset);
        NSTimeInterval dayLength = [self.sunset timeIntervalSinceDate:self.sunrise] / 60.0 / 60.0;
        NSLog(@"day length: %f", dayLength);
        double halfDayLength = dayLength / 2.0;
        NSDateComponents *components = [gregorian components:(NSYearCalendarUnit | NSMonthCalendarUnit | NSDayCalendarUnit | NSTimeZoneCalendarUnit) fromDate:self.sunrise];
        [components setTimeZone:[NSTimeZone timeZoneWithName:@"GMT"]];        
//        [components setHour:components.hour + (int)round(halfDayLength)];
//        double minutes = halfDayLength - (round(halfDayLength) * 60);
//        [components setMinute:(int)round(minutes)];
//        [components setSecond:(int)((minutes - round(minutes)) * 60)];
        [components setSecond:(int)(round(halfDayLength))];
        _solarNoon = [gregorian dateFromComponents:components];
    }
    if ((theseOps & FESSolarCalculationCivil) == FESSolarCalculationCivil) {
        computeSolarData(FESSolarCalculationCivil, FESSolarCalculationRising, FESSolarCalculationZenithCivil);
        computeSolarData(FESSolarCalculationCivil, FESSolarCalculationSetting, FESSolarCalculationZenithCivil);
    }
    if ((theseOps & FESSolarCalculationNautical) == FESSolarCalculationNautical) {
        computeSolarData(FESSolarCalculationNautical, FESSolarCalculationRising, FESSolarCalculationZenithNautical);
        computeSolarData(FESSolarCalculationNautical, FESSolarCalculationSetting, FESSolarCalculationZenithNautical);
    }
    if ((theseOps & FESSolarCalculationAstronomical) == FESSolarCalculationAstronomical) {
        computeSolarData(FESSolarCalculationAstronomical, FESSolarCalculationRising, FESSolarCalculationZenithAstronomical);
        computeSolarData(FESSolarCalculationAstronomical, FESSolarCalculationSetting, FESSolarCalculationZenithAstronomical);
    }

}

#pragma mark -
#pragma mark Class Methods

+ (int)julianDayNumberFromDate:(NSDate *)inDate
{
    // calculation of Julian Day Number (http://en.wikipedia.org/wiki/Julian_day ) from Gregorian Date
    NSCalendar *cal = [[NSCalendar alloc] initWithCalendarIdentifier:NSGregorianCalendar];
    NSDateComponents *components = [cal components:NSYearCalendarUnit | NSMonthCalendarUnit | NSDayCalendarUnit fromDate:inDate];
    NSLog(@"components: %@", components);
    int a = (14 - (int)[components month]) / 12;
    int y = (int)[components year] +  4800 - a;
    int m = (int)[components month] + (12 * a) - 3;
    int JulianDayNumber = (int)[components day] + (((153 * m) + 2) / 5) + (365 * y) + (y/4) - (y/100) + (y/400) - 32045;
    NSLog(@"JDN: %i", JulianDayNumber);
    return JulianDayNumber;
}

+ (NSDate *)gregorianDateFromJulianDayNumber:(int)julianDayNumber
{
    // calculation of Gregorian date from Julian Day Number ( http://en.wikipedia.org/wiki/Julian_day )
    int J = floor(julianDayNumber + 0.5);
    int j = J + 32044;
    int g = j / 146097;
    int dg = j - (j/146097) * 146097;
    int c = (dg / 36524 + 1) * 3 / 4;
    int dc = dg - c * 36524;
    int b = dc / 1461;
    int db = dc - (dc/1461) * 1461;
    int a = (db / 365 + 1) * 3 / 4;
    int da = db - a * 365;
    int y = g * 400 + c * 100 + b * 4 + a;
    int m = (da * 5 + 308) / 153 - 2;
    int d = da - (m + 4) * 153 / 5 + 122;
    NSDateComponents *components = [NSDateComponents new];
    components.timeZone = [NSTimeZone timeZoneWithName:@"GMT"];
    components.year = y - 4800 + (m + 2) / 12;
    components.month = ((m+2) - ((m+2)/12) * 12) + 1;
    components.day = d + 1;
    components.hour = 12;
    components.minute = 0;
    components.second = 0;
    NSCalendar *cal = [[NSCalendar alloc] initWithCalendarIdentifier:NSGregorianCalendar];
    return [cal dateFromComponents:components];
}

#pragma mark -
#pragma mark Calculation Ops

- (double)longitudeHourFromLongitude:(CLLocationDegrees)longitude
{
    double longitudeHour = longitude / 15.0;
    return longitudeHour;
}

- (double)approximateTimeFromDayOfYear:(NSUInteger)dayOfYear longitudeHour:(double)longitudeHour direction:(FESSolarCalculationDirection)direction
{
    double baseTime = 6;
    if ((direction & FESSolarCalculationSetting) == FESSolarCalculationSetting) {
        baseTime = 18;
    } 
    // t = N + ((baseTime - lngHour) / 24)
    double approximateTime = dayOfYear + ((baseTime - longitudeHour) / 24.0);
    return approximateTime;
}

- (double)sunsMeanAnomolyFromApproximateTime:(double)approximateTime
{
    // M = (0.9856 * t) - 3.289
    double sunsMeanAnomoly = (0.9856 * approximateTime) - 3.289;
    return sunsMeanAnomoly;
}

- (double)sunsTrueLongitudeFromMeanAnomoly:(double)meanAnomoly
{
    // L = M + (1.916 * sin(M)) + (0.020 * sin(2 * M)) + 282.634
    double meanAnomolyinRadians = meanAnomoly * toRadians;
    double trueLongitude = meanAnomoly + (1.916 * sin(meanAnomolyinRadians)) + (0.020 * sin(2 * meanAnomolyinRadians)) + 282.634;
    if (trueLongitude > 360.0) {
        trueLongitude -= 360.0;
    } else if (trueLongitude < 0.0) {
        trueLongitude += 360.0;        
    }
    return trueLongitude;
}

- (double)sunsRightAscensionFromTrueLongitude:(double)trueLongitude
{
    // RA = atan(0.91764 * tan(L))
    // Lquadrant  = (floor( L/90)) * 90
	// RAquadrant = (floor(RA/90)) * 90
	// RA = RA + (Lquadrant - RAquadrant)
    // RA = RA / 15
    
    double tanL = tan(trueLongitude * toRadians);
//    dNSLog(@"  ==> tanL: %f", tanL);
    double rightAscension = atan(0.91764 * tanL) * toDegrees;
    if (rightAscension > 360.0) {
        rightAscension -= 360.0;
    } else if (rightAscension < 0.0) {
        rightAscension += 360.0;
    }
//    dNSLog(@"  ==> RA: %f", rightAscension);
    double Lquadrant = floor(trueLongitude/90) * 90;
//    dNSLog(@"  ==> Lquad: %f", Lquadrant);
    double RAquadrant = floor(rightAscension/90) * 90;
//    dNSLog(@"  ==> RAquad: %f", RAquadrant);
    rightAscension += (Lquadrant - RAquadrant);
    rightAscension /=  15.0;
    return rightAscension;
}

- (double)sunsLocalHourAngleFromTrueLongitude:(double)trueLongitude latitude:(CLLocationDegrees)latitude zenith:(double)zenith direction:(FESSolarCalculationDirection)direction
{
    // sinDec = 0.39782 * sin(L)
	// cosDec = cos(asin(sinDec))
    
    double sinDeclination = 0.39782 * sin(trueLongitude * toRadians);
    double cosDeclination = cos(asin(sinDeclination));
    
    // cosH = (cos(zenith) - (sinDec * sin(latitude))) / (cosDec * cos(latitude))

    double latitudeInRadians = latitude * toRadians;
    double cosH = (cos(zenith * toRadians) - (sinDeclination * sin(latitudeInRadians))) / (cosDeclination * cos(latitudeInRadians));

    dNSLog(@"  ==> cosH: %f", cosH);
    
	// if (cosH >  1) 
	//  the sun never rises on this location (on the specified date)
	// if (cosH < -1)
	//  the sun never sets on this location (on the specified date)

    // TODO: figure out how to specify the sun never rises or sets (find the next day it does?)

    // if rising time is desired:
	//   H = 360 - acos(cosH)
	// if setting time is desired:
	//   H = acos(cosH)

    double sunsLocalHourAngle = acos(cosH) * toDegrees;
//    dNSLog(@"  ==> local hour angle: %f", sunsLocalHourAngle);
    if ((direction & FESSolarCalculationRising) == FESSolarCalculationRising) {
        sunsLocalHourAngle = 360.0 - sunsLocalHourAngle;
    }
//    dNSLog(@"  ==> local hour angle: %f", sunsLocalHourAngle);
	
    // H = H / 15
    sunsLocalHourAngle = sunsLocalHourAngle / 15.0;
//    dNSLog(@"  ==> local hour angle: %f", sunsLocalHourAngle);

    return sunsLocalHourAngle;
}

- (double)calculateLocalMeanTimeFromLocalHourAngle:(double)localHourAngle rightAscension:(double)rightAscension approximateTime:(double)approximateTime
{
    // T = H + RA - (0.06571 * t) - 6.622
    double localMeanTime = localHourAngle + rightAscension - (0.06571 * approximateTime) - 6.622;
    return localMeanTime;
}

- (double)convertToUTCFromLocalMeanTime:(double)localMeanTime longitudeHour:(double)longitudeHour
{
    // UT = T - lngHour
    // NOTE: UT potentially needs to be adjusted into the range [0,24) by adding/subtracting 24
    double timeinUTC = localMeanTime - longitudeHour;
    if (timeinUTC > 24.0) {
        timeinUTC -= 24.0;
    } else if (timeinUTC < 0.0) {
        timeinUTC += 24.0;
    }
    return timeinUTC;
}

@end
