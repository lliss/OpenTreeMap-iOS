// This file is part of the OpenTreeMap code.
//
// OpenTreeMap is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// OpenTreeMap is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with OpenTreeMap.  If not, see <http://www.gnu.org/licenses/>.

#import "OTMEnvironment.h"
#import "AZHttpRequest.h"
#import "OTMDetailCellRenderer.h"
#import "OTMFilterListViewController.h"
#import "OTMDetailCellRenderer.h"
#import "OTMMapDetailCellRenderer.h"
#import "OTMChoicesDetailCellRenderer.h"

@implementation OTMEnvironment

+ (id)sharedEnvironment
{
    static dispatch_once_t pred = 0;
    __strong static id _sharedObject = nil;
    dispatch_once(&pred, ^{
        _sharedObject = [[self alloc] init];
    });
    return _sharedObject;
}

/**
 Initialize the OTMEnvironment by reading values from the appropriate plist file.
 Expects that info.plist contains a 'Configuration' key.
 */
- (id)init
{
    self = [super init];
    if (!self) { return nil; }

    // Environment

    NSString* configuration = [[[NSBundle mainBundle] infoDictionary] objectForKey:@"Configuration"];
    NSBundle* bundle = [NSBundle mainBundle];
    NSString* environmentPListPath = [bundle pathForResource:configuration ofType:@"plist"];
    NSDictionary* environment = [[NSDictionary alloc] initWithContentsOfFile:environmentPListPath];

    // Environment - URLCache

    NSDictionary *urlCache = [environment valueForKey:@"URLCache"];

    [self setUrlCacheName:[urlCache valueForKey:@"Name"]];
    [self setUrlCacheQueueMaxContentLength:[urlCache valueForKey:@"QueueMaxContentLength"]];
    [self setUrlCacheInvalidationAgeInSeconds:[urlCache valueForKey:@"InvalidationAgeInSeconds"]];

    // Implementation

    NSString* implementationPListPath = [bundle pathForResource:@"Implementation" ofType:@"plist"];
    NSDictionary* implementation = [[NSDictionary alloc] initWithContentsOfFile:implementationPListPath];

    self.instance = [implementation objectForKey:@"instance"];
    self.apiKey = [implementation valueForKey:@"APIKey"];

    self.dateFormat = @"MMMM d, yyyy h:mm a";
    self.detailLatSpan = 0.0007;

    self.currencyUnit = [implementation objectForKey:@"OTMCurrencyDBHUnit"];
    if (self.currencyUnit == nil) {
        self.currencyUnit = @"$";
    }

    self.splashDelayInSeconds = 0;
    self.pendingActive = NO;
    self.viewBackgroundColor = [self colorFromArray:[implementation objectForKey:@"backgroundColor"] defaultColor:[UIColor whiteColor]];
    self.navBarTintColor = [self colorFromArray:[implementation objectForKey:@"tintColor"] defaultColor:nil];
    self.buttonTextColor = [self colorFromArray:[implementation objectForKey:@"buttonFontColor"] defaultColor:[UIColor whiteColor]];
    self.buttonImage = [UIImage imageNamed:@"btn_bg"];

    NSDictionary* url = [implementation valueForKey:@"APIURL"];

    [self setBaseURL:[NSString stringWithFormat:@"%@/%@/",
                      [url valueForKey:@"base"],
                      [url valueForKey:@"version"]]];

    // Implementation - MapView
    NSDictionary *mapView = [implementation valueForKey:@"MapView"];

    MKCoordinateSpan searchZoomCoordinateSpan = MKCoordinateSpanMake(0.0026, 0.0034);

    [self setMapViewSearchZoomCoordinateSpan:searchZoomCoordinateSpan];

    [self setUseOtmGeocoder:[[mapView valueForKey:@"UseOtmGeocoder"] boolValue]];

    [self setSearchRegionRadiusInMeters:[[mapView valueForKey:@"SearchRegionRadiusInMeters"] doubleValue]];

    [self setSearchSuffix:[mapView valueForKey:@"SearchSuffix"]];

    [self setLocationSearchTimeoutInSeconds:[mapView valueForKey:@"LocationSearchTimeoutInSeconds"]];

    [self setMapViewTitle:[mapView valueForKey:@"MapViewTitle"]];

    OTM2API* otmApi = [[OTM2API alloc] init];

    NSString* versionPlistPath = [bundle pathForResource:@"version" ofType:@"plist"];
    NSDictionary* version = [[NSDictionary alloc] initWithContentsOfFile:versionPlistPath];
    NSString *ver = [NSString stringWithFormat:@"ios-%@-b%@",
                         [version objectForKey:@"version"],
                         [version objectForKey:@"build"]];

    NSDictionary *headers = [NSDictionary dictionaryWithObjectsAndKeys:self.apiKey, @"X-API-Key",
                                          ver, @"ApplicationVersion",
                                          nil];

    NSURL *aurl = [NSURL URLWithString:[self baseURL]];
    AZHttpRequest* req = [[AZHttpRequest alloc] initWithURL:[self baseURL]];
    req.headers = headers;
    self.host = [NSString stringWithFormat:@"%@://%@:%@",
                          [aurl scheme],[aurl host],[aurl port]];

    AZHttpRequest* reqraw = [[AZHttpRequest alloc] initWithURL:self.baseURL];
    req.headers = headers;
    req.queue.maxConcurrentOperationCount = 3;

    otmApi.request = req;
    otmApi.noPrefixRequest = reqraw;

    self.api = otmApi;
    self.api2 = otmApi;

    return self;
}

-(void)setInstance:(NSString *)instance {
    _instance = instance;
    _api2.request.baseURL = [self.baseURL stringByAppendingFormat:@"%@/",instance];
    _api2.noPrefixRequest.baseURL = self.baseURL;
}

-(UIColor *)colorFromArray:(NSArray *)array defaultColor:(UIColor *)c {
    if (array == nil || [array count] != 4) {
        return c;
    } else {
        return [UIColor colorWithRed:[[array objectAtIndex:0] floatValue]
                               green:[[array objectAtIndex:1] floatValue]
                                blue:[[array objectAtIndex:2] floatValue]
                               alpha:[[array objectAtIndex:3] floatValue]];
    }
}

-(NSArray *)fieldKeys {
    return (NSArray* )self.fields;
}

- (void)updateEnvironmentWithDictionary:(NSDictionary *)dict {
    self.instance = [dict objectForKey:@"url"];
    self.instanceId = [dict objectForKey:@"id"];
    self.geoRev = [dict objectForKey:@"geoRev"];
    self.fields = [self fieldsFromDictArray:[dict objectForKey:@"fields"]];

    NSDictionary *missingAndStandardFilters = [dict objectForKey:@"search"];

    NSArray *regFilters = [self filtersFromDictArray:missingAndStandardFilters[@"standard"]];
    NSArray *missingFilters = [self missingFiltersFromDictArray:missingAndStandardFilters[@"missing"]];

    self.filters = [regFilters arrayByAddingObjectsFromArray:missingFilters];

    self.ecoFields = [self ecoFieldsFromDict:[dict objectForKey:@"eco"]];
    NSDictionary* center = [dict objectForKey:@"center"];

    CGFloat lat = [[center objectForKey:@"lat"] floatValue];
    CGFloat lng = [[center objectForKey:@"lng"] floatValue];

    CLLocationCoordinate2D initialLatLon =
        CLLocationCoordinate2DMake(lat, lng);

    MKCoordinateSpan initialCoordinateSpan =
        MKCoordinateSpanMake(1.0, 1.0);

    [self setMapViewInitialCoordinateRegion:
              MKCoordinateRegionMake(initialLatLon,
                                     initialCoordinateSpan)];
}

/**
 * All missing filters are boolean filters with "existenceFilter"
 * set to true.
 */
- (NSArray *)missingFiltersFromDictArray:(NSArray *)filterlist {
    NSMutableArray *filterArray = [NSMutableArray array];

    [filterlist enumerateObjectsUsingBlock:^(NSDictionary *filter, NSUInteger idx, BOOL *stop) {
            NSString *fieldKey = filter[@"identifier"];
            NSString *fieldName = filter[@"label"];

            OTMFilter *afilter = [[OTMBoolFilter alloc] initWithName:fieldName
                                                                 key:fieldKey
                                                     existanceFilter:YES];
            [filterArray addObject:afilter];
        }];

    return filterArray;
}

- (NSArray *)filtersFromDictArray:(NSArray *)filterlist {
    NSMutableArray *filterArray = [NSMutableArray array];

    [filterlist enumerateObjectsUsingBlock:^(NSDictionary *filter, NSUInteger idx, BOOL *stop) {
            NSString *fieldKey = filter[@"identifier"];
            NSString *fieldName = filter[@"label"];
            NSString *filterType = filter[@"search_type"];

            OTMFilter *afilter = nil;

            if ([filterType isEqualToString:@"CHOICES"]) {
                NSArray *filterChoices = filter[@"choices"];

                afilter = [[OTMChoiceFilter alloc] initWithName:fieldName
                                                           key:fieldKey
                                                       choices:filterChoices];
            }
            else if ([filterType isEqualToString:@"BOOL"]) {
                afilter = [[OTMBoolFilter alloc] initWithName:fieldName
                                                         key:fieldKey];
            }
            else if ([filterType isEqualToString:@"RANGE"]) {
                afilter = [[OTMRangeFilter alloc] initWithName:fieldName
                                                          key:fieldKey];

            }
            else if ([filterType isEqualToString:@"SPACE"]) {
                CGFloat space = [[filter valueForKey:@"space"] floatValue];

                afilter = [[OTMFilterSpacer alloc] initWithSpace:space];
            }

            if (afilter != nil) {
                [filterArray addObject:afilter];
            }
        }];

    return filterArray;
}

- (void)addSpeciesFieldsToArray:(NSMutableArray *)modelFields key:(NSString *)key {
    OTMDetailCellRenderer *commonNameRenderer =
        [[OTMLabelDetailCellRenderer alloc] initWithDataKey:[NSString stringWithFormat:@"%@.common_name", key]
                                               editRenderer:nil
                                                      label:@"Common Name"
                                                  formatter:nil];
    OTMDetailCellRenderer *sciNameRenderer =
        [[OTMLabelDetailCellRenderer alloc] initWithDataKey:[NSString stringWithFormat:@"%@.scientific_name", key]
                                               editRenderer:nil
                                                      label:@"Scientific Name"
                                                  formatter:nil];

    [modelFields addObject:sciNameRenderer];
    [modelFields addObject:commonNameRenderer];
}

- (void)addFieldsToArray:(NSMutableArray *)modelFields fromDict:(NSDictionary *)dict {
    NSString *field = [dict objectForKey:@"field_name"];
    NSString *displayField = [dict objectForKey:@"display_name"];
    NSString *key = [dict objectForKey:@"field_key"];
    BOOL writable = [[dict objectForKey:@"can_write"] boolValue];
    NSArray *choices = [dict objectForKey:@"choices"];

    if ((id)[NSNull null] == choices) {
        choices = nil;
    }

    NSString *unit = dict[@"units"];
    NSString *digitsV = dict[@"digits"];

    NSUInteger digits = digitsV != nil && digitsV != (id)[NSNull null]  ? [digitsV intValue] : 0;

    OTMFormatter *fmt = nil;
    if (unit != nil) {
        fmt = [[OTMFormatter alloc] initWithDigits:digits
                                             label:unit];
    }

    if ([field isEqualToString:@"geom"] ||
        [field isEqualToString:@"readonly"]) {
        // skip
    } else if ([field isEqualToString:@"species"]) {
        [self addSpeciesFieldsToArray:modelFields key:key];
    } else if ([field isEqualToString:@"diameter"]) {
        _dbhFormat = fmt;
        OTMDBHEditDetailCellRenderer *dbhEditRenderer =
            [[OTMDBHEditDetailCellRenderer alloc] initWithDataKey:key
                                                        formatter:fmt];

        [modelFields addObject:[[OTMLabelDetailCellRenderer alloc]
                                                   initWithDataKey:key
                                                      editRenderer:dbhEditRenderer
                                                             label:displayField
                                                         formatter:fmt]];
    } else if ([choices count] > 0) {
        OTMChoicesDetailCellRenderer *renderer =
            [[OTMChoicesDetailCellRenderer alloc] initWithDataKey:key
                                                            label:displayField
                                                         clickUrl:nil
                                                          choices:choices
                                                         writable:writable];

        [modelFields addObject:renderer];
    } else {
        OTMLabelEditDetailCellRenderer *editRenderer = nil;

        if (writable) {
            editRenderer = [[OTMLabelEditDetailCellRenderer alloc]
                                               initWithDataKey:key
                                                         label:displayField
                                                      keyboard:UIKeyboardTypeDefault
                                                     formatter:fmt];
        }
        [modelFields addObject:[[OTMLabelDetailCellRenderer alloc]
                                                       initWithDataKey:key
                                                          editRenderer:editRenderer
                                                                 label:displayField
                                                             formatter:fmt]];
    }
}

- (NSArray *)fieldsFromDictArray:(NSDictionary *)modelmap {
    NSMutableArray *fieldArray = [NSMutableArray array];

    // Add the minimap at the top
    [fieldArray addObject:[NSArray arrayWithObject:[[OTMMapDetailCellRenderer alloc] initWithDataKey:@"geom"]]];

    /**
     * Species models come along for the ride but we don't really
     * care for them here
     */
    NSArray *validModels = [NSArray arrayWithObjects:@"tree", @"plot", nil];

    [modelmap enumerateKeysAndObjectsUsingBlock:^(NSString *model, NSArray* fieldlist, BOOL *stop) {
        if ([validModels containsObject:model]) {
            NSMutableArray *modelFields = [NSMutableArray array];

            [fieldlist enumerateObjectsUsingBlock:^(NSDictionary *dict, NSUInteger idx, BOOL *stop) {
                    [self addFieldsToArray:modelFields fromDict:dict];
                }];

            [fieldArray addObject:modelFields];
        }
    }];

    return fieldArray;
}

- (NSArray*)ecoFieldsFromDict:(NSDictionary*)ecoDict {
    if ([ecoDict objectForKey:@"supportsEcoBenefits"]) {
        NSMutableArray *fieldArray = [NSMutableArray array];
        NSArray *benefits = [ecoDict objectForKey:@"benefits"];
        [benefits enumerateObjectsUsingBlock:^(NSDictionary *fieldDict, NSUInteger idx, BOOL *stop) {
            // Currently, we create the same type of cell renderer without regard to
            // any of the field details
            [fieldArray addObject:[[OTMBenefitsDetailCellRenderer alloc] initWithLabel:[fieldDict objectForKey:@"label"] index:idx]];
        }];
        // To be consistant with the editable fields, the eco fields are wrapped in a containing
        // array that represents the field group. This may be useful
        // in the future when there may be multiple sets of eco benefits.
        return [NSArray arrayWithObject:fieldArray];
    } else {
        return [[NSArray alloc] init];
    }
}

@end
