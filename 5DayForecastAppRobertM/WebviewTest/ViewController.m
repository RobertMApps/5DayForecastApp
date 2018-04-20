//
//  ViewController.m
//  WebviewTest
//
//  Created by Robert M on 4/17/18.
//  Copyright © 2018 Robert. All rights reserved.
//

#import "ViewController.h"
#import "vw_forecast.h"

@interface ViewController ()
@property (strong, nonatomic) IBOutlet UIButton *btn_confirm;
@property (strong, nonatomic) IBOutlet UITextField *txt_location;
@property (strong, nonatomic) IBOutlet UISegmentedControl *seg_day;
@property (strong, nonatomic) IBOutlet vw_forecast *view_forecast;
//Ignore this view; had issues when first laying out my storyboard so an IBOutlet got lost to the nether and the project crashes if this isn't here
@property (strong, nonatomic) UIView *view_tomorrow;
@property (strong, nonatomic) IBOutlet UILabel *lbl_loading;
@property (strong, nonatomic) IBOutlet UISwitch *swt_fOrC;
@property (strong, nonatomic) NSDictionary *forecastInfo;
@property (strong, nonatomic) NSDictionary *geocodeInfo;
@property (strong, nonatomic) NSArray *fiveDayForecast;
@end

static NSString *const WEATHER_RECEIVED = @"weatherReceivedNotification";
static NSString *const LATLONG_RECEIVED = @"latlongReceivedNotification";
static NSString *const googleGeocode = @"https://maps.google.com/maps/api/geocode/json?address=%@&key=AIzaSyAHrYLoSJhxmxPru2LFIMIo3i5nDdnAAWw";
@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    [self.btn_confirm addTarget: self action: @selector(findWeatherPressed) forControlEvents:UIControlEventTouchUpInside];
    [self.btn_confirm setTitle:@"Get Forecast" forState:UIControlStateNormal];
    [self.btn_confirm setTitle:@"Working..." forState:UIControlStateDisabled];
    
    [self.txt_location addTarget:self action:@selector(locationEditBegin) forControlEvents:UIControlEventEditingDidBegin];
    [self.txt_location setText: @"Los Angeles, California"];
    
    [self.swt_fOrC addTarget:self action:@selector(updateForecastView) forControlEvents:UIControlEventValueChanged];
    
    [self.seg_day addTarget:self action:@selector(updateForecastView) forControlEvents:UIControlEventValueChanged];
    
    _forecastInfo = nil;
    _geocodeInfo = nil;
    _view_forecast.lbl_date.text = @"Tomorrow:";
    _view_forecast.lbl_high.text = @"";
    _view_forecast.lbl_low.text = @"";
    _view_forecast.lbl_desc.text = @"";
    
    _lbl_loading.text = @"Enter a City and/or State";
    
    [self setup5DayArray];
    [self updateForecastView];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(weatherReceived) name:WEATHER_RECEIVED object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(latlongReceived) name:LATLONG_RECEIVED object:nil];
}


- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

-(void)findWeatherPressed{
    //If the text is empty, don't try to search
    if(_txt_location.text.length <= 0 || !_txt_location.text){
        return;
    }
    //Make sure the keyboard gets dismissed
    [_txt_location resignFirstResponder];
    //Don't let illegal/unnecessary characters go through
    NSString *searchText = [_txt_location.text stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet alphanumericCharacterSet]];
    //We'll go through google to get lat and long (Google's Geocoding is also very good at getting back someplace, no matter what the user enters(try searching "Mary Had a Little Lamb" or some such nonsense, and you'll see what I mean))
    NSURL *geocodeURL = [NSURL URLWithString: [NSString stringWithFormat:googleGeocode, searchText]];
    NSURLRequest *geocodeRequest = [NSURLRequest requestWithURL:geocodeURL];
    
    //Send off our network request, and when we get it back set our info and post a notification.
    [[[NSURLSession sessionWithConfiguration: NSURLSessionConfiguration.defaultSessionConfiguration] dataTaskWithRequest: geocodeRequest completionHandler:^(NSData *data, NSURLResponse *response, NSError *error){
            if(data.length>0&&error == nil){
            self.geocodeInfo = [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL];
            [[NSNotificationCenter defaultCenter] postNotificationName:LATLONG_RECEIVED object:self];
            }
    }] resume];
    //Lock our UI to prevent spamming network requests
    _lbl_loading.text = @"Working...";
    [_btn_confirm setEnabled:false];
}

#pragma mark data recieved notifications
-(void)latlongReceived{
    //Notification posted that we got info back, grab the relevant info from the results
    //TODO IF HAD MORE TIME: check status on return, if not "OK" handle error properly
    if(![[_geocodeInfo objectForKey:@"status"] isEqualToString:@"OK"]){
        return;
    }
    NSDictionary *latlong = [[[[_geocodeInfo objectForKey:@"results"] objectAtIndex:0] objectForKey:@"geometry"] objectForKey:@"location"];
     NSString *latitude = [latlong objectForKey:@"lat"];
    NSString *longitude = [latlong objectForKey:@"lng"];
    
    NSURL *weatherURL = [NSURL URLWithString: [NSString stringWithFormat:@"https://api.openweathermap.org/data/2.5/forecast?lat=%@&lon=%@&APPID=2216557dfbd2d013e7559ef866e41b96", latitude, longitude]];
    NSURLRequest *weatherRequest = [NSURLRequest requestWithURL:weatherURL];
    //Make our weather request, and when we get it back, set our data and post notification
    [[[NSURLSession sessionWithConfiguration: NSURLSessionConfiguration.defaultSessionConfiguration] dataTaskWithRequest: weatherRequest completionHandler:^(NSData *data, NSURLResponse *response, NSError *error){
        dispatch_async(dispatch_get_main_queue(), ^{
            if(data.length>0&&error == nil){
                self.forecastInfo = [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL];
                [[NSNotificationCenter defaultCenter] postNotificationName:WEATHER_RECEIVED object:self];
            }
        });
    }] resume];
}
-(void)weatherReceived{
    _lbl_loading.text = @"Enter a City and/or State";
    //To confirm exactly what the geocoding came back with, we'll set the input text to the city returned in the cached geocode info
    _txt_location.text = [[[_geocodeInfo objectForKey:@"results"] objectAtIndex:0] objectForKey:@"formatted_address"];
    [self unlockButton];
    //Values for handling days (0-7 are tomorrow, counting from midnight to 9pm, since API gives data back in 3 hour increments). Noon is 9 hours before 9 pm, so 3 less than the end of the day
    int tomorrow = 7;
    int twodays = 14;
    int threedays = 21;
    int fourDays = 28;
    int fiveDays = 35;
    int noon = 3;
    
    //We're going to collect all weather values for a given day, then sort them to get the high and low over the course of that day
    NSMutableArray *temperatureRange = [[NSMutableArray alloc] initWithCapacity:0];
    NSSortDescriptor *lowestToHighest = [NSSortDescriptor sortDescriptorWithKey:@"self" ascending: YES];
                                    
    //Array of weather for next 5 days, in 3 hour increments (starting tomorrow at 12am)
    NSArray *forecastArray = _forecastInfo[@"list"];
    int i = 0;
    for(NSDictionary *mainDict in forecastArray){
        NSDate *date = [NSDate dateWithTimeIntervalSince1970:[mainDict[@"dt"]doubleValue]];
        NSUInteger units = NSCalendarUnitYear|NSCalendarUnitMonth|NSCalendarUnitDay;
        //Should give use today at 0 hours, IE Midnight
        NSDateComponents *comps = [[NSCalendar currentCalendar]components:units fromDate:[NSDate date]];
        //We always want to start with tomorrow, so we go until we've got the data from 24 hours past midnight this morning
        if([[NSCalendar currentCalendar] isDate:date inSameDayAsDate:[[NSCalendar currentCalendar]dateFromComponents:comps]]){
            continue;
        }
        //Data with the temperature/pressure/etc
        NSDictionary *temperatureDict = mainDict[@"main"];
        //Data with the weather/rainfall/description/weather icon
        NSDictionary *weatherDict = [[mainDict objectForKey:@"weather"] objectAtIndex:0];
        
        [temperatureRange addObject:temperatureDict[@"temp_max"]];
        [temperatureRange addObject:temperatureDict[@"temp_min"]];
        //At the end of a given day, get the min and max temps recorded, the date string, then empty the temperature array
        if(i==tomorrow||i==twodays||i==threedays||i==fourDays||i==fiveDays){
            [temperatureRange sortUsingDescriptors:[NSArray arrayWithObject: lowestToHighest]];
            [self setHigh: [[temperatureRange lastObject] doubleValue] forDay: i/7-1];
            [self setLow: [[temperatureRange firstObject] doubleValue] forDay: i/7-1];
            [temperatureRange removeAllObjects];
            
            NSDateFormatter *dateFormat = [[NSDateFormatter alloc] init];
            [dateFormat setDateFormat:@"E, MMM d"];
            [self setDate:[dateFormat stringFromDate:date] forDay:i/7-1];
        }
        //When we reach noon for a given day, we grab the description and icon for that day (just to get the overall idea of the day, since we only show it per day instead of per time)
        if(i==tomorrow-noon||i==twodays-noon||i==threedays-noon||i==fourDays-noon||i==fiveDays-noon){
            //Set basic description of weather
            NSString *description = [weatherDict objectForKey:@"description"];
            [self setDescription:description forDay:(i+noon)/7-1];
            //Get icon for weather conditions
            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                //Make request on background thread
                NSString *iconURLString = [NSString stringWithFormat:@"https://openweathermap.org/img/w/%@.png", weatherDict[@"icon"]];
                NSData *data = [[NSData alloc] initWithContentsOfURL:[NSURL URLWithString:iconURLString]];
                dispatch_async(dispatch_get_main_queue(), ^{
                    //Change UI on main thread
                    if(!!data){
                        [self setWeatherImage:[[UIImage alloc] initWithData:data] forDay:(i+noon)/7-1];
                    }
                });
            });
        }
        i++;
    }
    [self updateForecastView];
}

#pragma mark UI methods
-(void)unlockButton{
    [_btn_confirm setEnabled:true];
}
-(void)locationEditBegin{
    _txt_location.text = @"";
}
#pragma mark temperature help methods
                                        
//API returns temp in kelvin
-(double)celsiusFromKelvin:(double)temp{
    temp -= 273.15;
    return temp;
}
-(double)farenheitFromKelvin:(double)temp{
    temp -= 273.15;
    temp = temp*1.8+32;
    return temp;
}
-(double)farenheitFromCelsius:(double)temp{
    temp = temp*1.8+32;
    return temp;
}
-(double)celsiusFromFarenheit:(double)temp{
    temp = (temp-32)/1.8;
    return temp;
}
#pragma mark Add info to forecast
-(void)setDescription: (NSString*)description forDay: (int)day{
    if(day>=5||day<0){
        return;
    }
     [_fiveDayForecast[day] setValue:description forKey:@"description"];
}
-(void)setDate: (NSString*)date forDay: (int)day{
    if(day>=5||day<0){
        return;
    }
    [_fiveDayForecast[day] setValue:date forKey:@"date"];
}
-(void)setHigh: (double)high forDay: (int)day{
    if(day>=5||day<0){
        return;
    }
    high = [self celsiusFromKelvin:high];
    [_fiveDayForecast[day] setValue: [NSString stringWithFormat:@"%.2lfC°",high] forKey:@"highC"];
    high = [self farenheitFromCelsius:high];
    [_fiveDayForecast[day] setValue: [NSString stringWithFormat:@"%.2lfF°",high] forKey:@"highF"];
}
-(void)setLow: (double)low forDay: (int)day{
    if(day>=5||day<0){
        return;
    }
    low = [self celsiusFromKelvin:low];
    [_fiveDayForecast[day] setValue: [NSString stringWithFormat:@"%.2lfC°",low] forKey:@"lowC"];
    low = [self farenheitFromCelsius:low];
    [_fiveDayForecast[day] setValue: [NSString stringWithFormat:@"%.2lfF°",low] forKey:@"lowF"];
}
-(void)setWeatherImage:(UIImage*)image forDay: (int)day{
    if(day>=5||day<0){
        return;
    }
    [_fiveDayForecast[day] removeObjectForKey:@"image"];
    [_fiveDayForecast[day] setValue:image forKey: @"image"];
    //Make sure our new image is set by just updating all the info
    [self updateForecastView];
}
-(void)updateForecastView{
    long selectedDate = [_seg_day selectedSegmentIndex];
    _view_forecast.lbl_date.text = [_fiveDayForecast[selectedDate] valueForKey:@"date"];
    _view_forecast.lbl_desc.text = [_fiveDayForecast[selectedDate] valueForKey:@"description"];
    if(_swt_fOrC.isOn){
        //Farenheit selected
        _view_forecast.lbl_high.text = [_fiveDayForecast[selectedDate] valueForKey:@"highF"];
        _view_forecast.lbl_low.text = [_fiveDayForecast[selectedDate] valueForKey:@"lowF"];
    }
    else{
        //Celsius selected
        _view_forecast.lbl_high.text = [_fiveDayForecast[selectedDate] valueForKey:@"highC"];
        _view_forecast.lbl_low.text = [_fiveDayForecast[selectedDate] valueForKey:@"lowC"];
    }
    [_view_forecast.img_desc setImage:[_fiveDayForecast[selectedDate] valueForKey:@"image"]];
}
#pragma mark setup helper methods
-(void)setup5DayArray{
    //Initializes the array with dictionaries for each day's forecast
    NSMutableArray *setupArray = [NSMutableArray arrayWithCapacity:5];
    for(int i=0; i<5; i++){
        //Add blank dictionary for each of the days
        NSString *placeholder = @"";
        switch(i){
            case 0: placeholder = @"Tomorrow";
                break;
            case 1: placeholder = @"Two Days";
                break;
            case 2: placeholder = @"Three Days";
                break;
            case 3: placeholder = @"Four Days";
                break;
            case 4: placeholder = @"Five Days";
                break;
            default: placeholder = @"";
                break;
        }
        NSMutableDictionary *dict = [NSMutableDictionary dictionaryWithCapacity:7];
        dict[@"date"]=placeholder;
        dict[@"highC"]=@"0";
        dict[@"highF"]=@"0";
        dict[@"lowC"]=@"0";
        dict[@"lowF"]=@"0";
        dict[@"description"]=@"Nothing yet";
        dict[@"image"]=[UIImage alloc];
        [setupArray addObject:dict];
    }
    _fiveDayForecast = [[NSArray alloc] initWithArray:setupArray];
}

-(void)dealloc{
    //Stop observing all notifications
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

@end
