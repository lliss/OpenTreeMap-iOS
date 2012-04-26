//                                                                                                                
// Copyright (c) 2012 Azavea                                                                                
//                                                                                                                
// Permission is hereby granted, free of charge, to any person obtaining a copy                                   
// of this software and associated documentation files (the "Software"), to                                       
// deal in the Software without restriction, including without limitation the                                     
// rights to use, copy, modify, merge, publish, distribute, sublicense, and/or                                    
//  sell copies of the Software, and to permit persons to whom the Software is                                    
// furnished to do so, subject to the following conditions:                                                       
//                                                                                                                
// The above copyright notice and this permission notice shall be included in                                     
// all copies or substantial portions of the Software.                                                            
//                                                                                                                
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR                                     
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,                                       
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE                                    
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER                                         
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,                                  
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN                                      
// THE SOFTWARE.                                                                                                  
//  

#import "OTMMapViewController.h"
#import "AZWMSOverlay.h"
#import "AZPointOffsetOverlay.h"
#import "OTMEnvironment.h"
#import "OTMAPI.h"
#import "OTMTreeDetailViewController.h"
#import "OTMAppDelegate.h"
#import "OTMDetailCellRenderer.h"
#import "OTMAddTreeAnnotationView.h"

@interface OTMMapViewController ()
- (void)setupMapView;

-(void)slideDetailUpAnimated:(BOOL)anim;
-(void)slideDetailDownAnimated:(BOOL)anim;
/**
 Append single-tap recognizer to the view that calls handleSingleTapGesture:
 */
- (void)addGestureRecognizersToView:(UIView *)view;
@end

@implementation OTMMapViewController

@synthesize lastClickedTree, detailView, treeImage, dbh, species, address, detailsVisible, selectedPlot, mode, locationManager, mostAccurateLocationResponse, mapView, addTreeAnnotation, addTreeHelpView, addTreeHelpLabel, addTreePlacemark;

- (void)viewDidLoad
{
    self.detailsVisible = NO;

    [self changeMode:Select];

    self.title = [[OTMEnvironment sharedEnvironment] mapViewTitle];
    if (!self.title) {
        self.title = @"Tree Map";
    }

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(updatedImage:)
                                                 name:kOTMMapViewControllerImageUpdate
                                               object:nil];    
    
    [super viewDidLoad];
    [self slideDetailDownAnimated:NO];
    [self slideAddTreeHelpDownAnimated:NO];
     
    [self setupMapView];
}

- (void)viewDidUnload
{
    [super viewDidUnload];
    
    [[NSNotificationCenter defaultCenter] removeObserver:self
                                                    name:kOTMMapViewControllerImageUpdate
                                                  object:nil];
}

-(void)updatedImage:(NSNotification *)note {
    self.treeImage.image = note.object;
}

- (void)viewWillAppear:(BOOL)animated
{
    MKCoordinateRegion region = [(OTMAppDelegate *)[[UIApplication sharedApplication] delegate] mapRegion];
    [mapView setRegion:region];
}

/**
 This method is designed to mimic the response from the geo plot API so that the OTMTreeDetailViewController is always
 working with the same dictionary schema.
 */
- (NSMutableDictionary *)createAddTreeDictionaryFromAnnotation:(MKPointAnnotation *)annotation placemark:(CLPlacemark *)placemark
{
    NSMutableDictionary *geometryDict = [[NSMutableDictionary alloc] init];
    [geometryDict setObject:[NSNumber numberWithFloat:annotation.coordinate.latitude] forKey:@"lat"];
    [geometryDict setObject:[NSNumber numberWithFloat:annotation.coordinate.longitude] forKey:@"lon"];
    [geometryDict setObject:[NSNumber numberWithInt:4326] forKey:@"srid"];

    NSMutableDictionary *addTreeDict = [[NSMutableDictionary alloc] init];
    [addTreeDict setObject:geometryDict forKey:@"geometry"];

    if (addTreePlacemark) {
        [addTreeDict setObject:addTreePlacemark.name forKey:@"geocode_address"];
        [addTreeDict setObject:addTreePlacemark.name forKey:@"edit_address_street"];
    } else {
        // geocode_address and edit_street_address are required by the Django application
        // but they are not srictly nessesary to have a functional app.
        [addTreeDict setObject:@"No Address" forKey:@"geocode_address"];
        [addTreeDict setObject:@"No Address" forKey:@"edit_address_street"];
    }

    return addTreeDict;
}

- (void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender 
{
    if ([segue.identifier isEqualToString:@"Details"]) {
        OTMTreeDetailViewController *dest = segue.destinationViewController;
        [dest view]; // Force it load its view
        dest.delegate = self;

        if (self.mode == Select) {
            dest.data = self.selectedPlot;
        } else {
            dest.data = [self createAddTreeDictionaryFromAnnotation:self.addTreeAnnotation placemark:self.addTreePlacemark];
        }
        
        id keys = [NSArray arrayWithObjects:
                     [NSArray arrayWithObjects:                      
                      [NSDictionary dictionaryWithObjectsAndKeys:
                       @"id", @"key",
                       @"Tree Number", @"label", 
                       [NSNumber numberWithBool:YES], @"readonly",
                       nil],
                      [NSDictionary dictionaryWithObjectsAndKeys:
                       @"tree.sci_name", @"key",
                       @"Scientific Name", @"label",
                      [NSNumber numberWithBool:YES], @"readonly", nil],                      
                      [NSDictionary dictionaryWithObjectsAndKeys:
                       @"tree.dbh", @"key",
                       @"Trunk Diameter", @"label", 
                       @"fmtIn:", @"format",  
                       @"OTMDBHEditDetailCellRenderer", @"editClass",
                       nil],
                      [NSDictionary dictionaryWithObjectsAndKeys:
                       @"tree.height", @"key",
                       @"Tree Height", @"label",
                       @"fmtM:", @"format",  
                       nil],
                      [NSDictionary dictionaryWithObjectsAndKeys:
                       @"tree.canopy_height", @"key",
                       @"Canopy Height", @"label", 
                       @"fmtM:", @"format", 
                       nil],
                      nil],
                   [NSArray arrayWithObjects:
                    [NSDictionary dictionaryWithObjectsAndKeys:
                     @"width", @"key",
                     @"Plot Width", @"label", 
                     @"fmtFt:", @"format", 
                     nil],
                    [NSDictionary dictionaryWithObjectsAndKeys:
                     @"length", @"key",
                     @"Plot Length", @"label", 
                     @"fmtFt:", @"format", 
                     nil],
                      [NSDictionary dictionaryWithObjectsAndKeys:
                       @"powerlines", @"key",
                       @"Powerlines", @"label", 
                       @"OTMChoicesDetailCellRenderer", @"class",
                       @"powerline_conflict_potential", @"fname",
                       nil],
                    [NSDictionary dictionaryWithObjectsAndKeys:
                     @"sidewalk_damage", @"key",
                     @"Sidewalk", @"label", 
                     @"OTMChoicesDetailCellRenderer", @"class",
                     @"sidewalk_damage", @"fname",
                     nil],
                    [NSDictionary dictionaryWithObjectsAndKeys:
                     @"canopy_condition", @"key",
                     @"Canopy Condition", @"label", 
                     @"OTMChoicesDetailCellRenderer", @"class",
                     @"canopy_condition", @"fname",
                     nil],
                    nil],
                     nil];
        
        NSMutableArray *sections = [NSMutableArray array];
        for(NSArray *sectionArray in keys) {
            NSMutableArray *section = [NSMutableArray array];
            
            for(NSDictionary *rowDict in sectionArray) {
                [section addObject:
                 [OTMDetailCellRenderer cellRendererFromDict:rowDict]];
            }
            
            [sections addObject:section];
        }
        
        dest.keys = sections;
        dest.imageView.image = self.treeImage.image;
        if (self.mode != Select) {
            // When adding a new tree the detail view is automatically in edit mode
            [dest startEditing:self];
        }
    }
}

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation
{
    if ([[UIDevice currentDevice] userInterfaceIdiom] == UIUserInterfaceIdiomPhone) {
        return (interfaceOrientation != UIInterfaceOrientationPortraitUpsideDown);
    } else {
        return YES;
    }
}

- (IBAction)setMapMode:(UISegmentedControl *)sender {
    switch (sender.selectedSegmentIndex) {
        case 0:
            self.mapView.mapType = MKMapTypeStandard;
            break;
        case 1:
            self.mapView.mapType = MKMapTypeSatellite;
            break;
        default:
            self.mapView.mapType = MKMapTypeHybrid;
            break;
    }
}

#pragma mark Detail View

-(void)setDetailViewData:(NSDictionary*)plot {
    NSString* tdbh = nil;
    NSString* tspecies = nil;
    NSString* taddress = nil;
    
    NSDictionary* tree;
    if ((tree = [plot objectForKey:@"tree"]) && [tree isKindOfClass:[NSDictionary class]]) {
        NSString* dbhValue = [tree objectForKey:@"dbh"];
        
        if (dbhValue != nil && ![[NSString stringWithFormat:@"%@", dbhValue] isEqualToString:@"<null>"]) {
            tdbh =  [NSString stringWithFormat:@"%@", dbhValue];   
        }
        
        tspecies = [NSString stringWithFormat:@"%@",[tree objectForKey:@"species_name"]];
    }
    
    taddress = [plot objectForKey:@"address"];
    
    if (tdbh == nil || tdbh == @"<null>") { tdbh = @"Diameter"; }
    if (tspecies == nil || tspecies == @"<null>") { tspecies = @"Species"; }
    if (taddress == nil || taddress == @"<null>") { taddress = @"Address"; }
    
    [self.dbh setText:tdbh];
    [self.species setText:tspecies];
    [self.address setText:taddress];
}


-(void)slideUpBottomDockedView:(UIView *)view animated:(BOOL)anim {
    if (anim) {
        [UIView beginAnimations:[NSString stringWithFormat:@"slideup%@", view] context:nil];
        [UIView setAnimationCurve:UIViewAnimationCurveEaseOut];
        [UIView setAnimationDuration:0.2];
    }
    
    [view setFrame:
     CGRectMake(0,
                self.view.bounds.size.height - view.frame.size.height,
                self.view.bounds.size.width,
                view.frame.size.height)];
    
    if (anim) {
        [UIView commitAnimations];
    }
}

-(void)slideDetailUpAnimated:(BOOL)anim {
    [self slideUpBottomDockedView:self.detailView animated:anim];
    self.detailsVisible = YES;
}

-(void)slideAddTreeHelpUpAnimated:(BOOL)anim {
    [self slideUpBottomDockedView:self.addTreeHelpView animated:anim];
}

-(void)slideDownBottomDockedView:(UIView *)view animated:(BOOL)anim {
    if (anim) {
        [UIView beginAnimations:[NSString stringWithFormat:@"slidedown%@", view] context:nil];
        [UIView setAnimationCurve:UIViewAnimationCurveEaseIn];
        [UIView setAnimationDuration:0.2];
    }    
    
    [view setFrame:
     CGRectMake(0,
                self.view.bounds.size.height,
                self.view.bounds.size.width, 
                view.frame.size.height)];
    
    if (anim) {
        [UIView commitAnimations];
    }
}

-(void)slideDetailDownAnimated:(BOOL)anim {
    [self slideDownBottomDockedView:self.detailView animated:anim];
    self.detailsVisible = NO;
}

-(void)slideAddTreeHelpDownAnimated:(BOOL)anim {
    [self slideDownBottomDockedView:self.addTreeHelpView animated:anim];
}

#pragma mark Map view setup

- (void)setupMapView
{
    OTMEnvironment *env = [OTMEnvironment sharedEnvironment];

    MKCoordinateRegion region = [env mapViewInitialCoordinateRegion];
    [mapView setRegion:region animated:FALSE];
    [mapView regionThatFits:region];
    [mapView setDelegate:self];
    [self addGestureRecognizersToView:mapView];

    AZWMSOverlay *overlay = [[AZWMSOverlay alloc] init];

    [overlay setServiceUrl:[env geoServerWMSServiceURL]];
    [overlay setLayerNames:[env geoServerLayerNames]];
    [overlay setFormat:[env geoServerFormat]];

    [mapView addOverlay:overlay];
}

- (void)addGestureRecognizersToView:(UIView *)view
{
    UITapGestureRecognizer *singleTapRecognizer = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleSingleTapGesture:)];
    singleTapRecognizer.numberOfTapsRequired = 1;
    singleTapRecognizer.numberOfTouchesRequired = 1;
    [view addGestureRecognizer:singleTapRecognizer];

    UITapGestureRecognizer *doubleTapRecognizer = [[UITapGestureRecognizer alloc] init];
    doubleTapRecognizer.numberOfTapsRequired = 2;
    doubleTapRecognizer.numberOfTouchesRequired = 1;

    // In order to pass double-taps to the underlying MKMapView the delegate for this recognizer (self) needs
    // to return YES from gestureRecognizer:shouldRecognizeSimultaneouslyWithGestureRecognizer:
    doubleTapRecognizer.delegate = self;
    [view addGestureRecognizer:doubleTapRecognizer];

    // This prevents delays the single-tap recognizer slightly and ensures that it will _not_ fire if there is
    // a double-tap
    [singleTapRecognizer requireGestureRecognizerToFail:doubleTapRecognizer];
}

#pragma mark mode management methods

- (void)clearSelectedTree
{
    if (self.lastClickedTree) {
        [self.mapView removeAnnotation:self.lastClickedTree];
        self.lastClickedTree = nil;
    }
    if (self.detailsVisible) {
        [self slideDetailDownAnimated:YES];
    }
}

- (void)changeMode:(OTMMapViewControllerMapMode)newMode
{
    if (newMode == self.mode) {
        return;
    }

    if (newMode == Add) {
        self.navigationItem.title = @"Add A Tree";
        self.navigationItem.leftBarButtonItem.title = @"Cancel";
        self.navigationItem.leftBarButtonItem.target = self;
        self.navigationItem.leftBarButtonItem.action = @selector(cancelAddTree);
        self.navigationItem.rightBarButtonItem = nil;

        [self clearSelectedTree];
        self.addTreeHelpLabel.text = @"Step 1: Tap the new tree location";
        [self slideAddTreeHelpUpAnimated:YES];

    } else if (newMode == Move) {
        self.navigationItem.leftBarButtonItem.title = @"Cancel";
        self.navigationItem.leftBarButtonItem.target = self;
        self.navigationItem.leftBarButtonItem.action = @selector(cancelMoveNewTree);
        self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"Next" style:UIBarButtonItemStyleBordered target:self action:@selector(showNewTreeEditView)];
        [self crossfadeLabel:self.addTreeHelpLabel newText:@"Step 2: Move tree into position then click Next"];

    } else if (newMode == Select) {
        if (self.addTreeAnnotation) {
            [self.mapView removeAnnotation:self.addTreeAnnotation];
            self.addTreeAnnotation = nil;
        }
        self.navigationItem.title = [[OTMEnvironment sharedEnvironment] mapViewTitle];
        self.navigationItem.leftBarButtonItem.title = @"Filter";
        self.navigationItem.leftBarButtonItem.target = self;
        self.navigationItem.leftBarButtonItem.action = @selector(showFilters);
        self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAdd target:self action:@selector(startAddingTree)];
        [self slideAddTreeHelpDownAnimated:YES];
    }

    self.mode = newMode;
}

- (void)crossfadeLabel:(UILabel *)label newText:(NSString *)newText
{
    [UIView beginAnimations:[NSString stringWithFormat:@"crossfadelabel%@", label] context:nil];
    [UIView setAnimationCurve:UIViewAnimationCurveEaseOut];
    [UIView setAnimationDuration:0.6];

    label.alpha = 0;
    label.text = newText;
    label.alpha = 1;

    [UIView commitAnimations];
}

- (void)slideAddTreeAnnotationToCoordinate:(CLLocationCoordinate2D)coordinate
{
    [UIView beginAnimations:[NSString stringWithFormat:@"slideannotation%@", self.addTreeAnnotation] context:nil];
    [UIView setAnimationCurve:UIViewAnimationCurveEaseOut];
    [UIView setAnimationDuration:0.2];

    self.addTreeAnnotation.coordinate = coordinate;

    [UIView commitAnimations];
}

- (void)cancelAddTree
{
    [self changeMode:Select];
}

- (void)cancelMoveNewTree
{
    [self changeMode:Select];
}

- (void)showFilters
{
    // TODO: hide the wizard label
}

- (void)startAddingTree
{
    [self changeMode:Add];
}

- (void)showNewTreeEditView
{
    [self performSegueWithIdentifier:@"Details" sender:self];
}

#pragma mark tap response methods

- (void)selectTreeNearCoordinate:(CLLocationCoordinate2D)coordinate
{
    [[[OTMEnvironment sharedEnvironment] api] getPlotsNearLatitude:coordinate.latitude
                                                         longitude:coordinate.longitude
                                                          callback:^(NSArray* plots, NSError* error)
     {
         if ([plots count] == 0) { // No plots returned
             [self slideDetailDownAnimated:YES];
         } else {
             NSDictionary* plot = [plots objectAtIndex:0];

             self.selectedPlot = [plot mutableDeepCopy];

             NSDictionary* geom = [plot objectForKey:@"geometry"];

             NSDictionary* tree = [plot objectForKey:@"tree"];

             self.treeImage.image = nil;

             if (tree && [tree isKindOfClass:[NSDictionary class]]) {
                 NSArray* images = [tree objectForKey:@"images"];

                 if (images && [images isKindOfClass:[NSArray class]] && [images count] > 0) {
                     int imageId = [[[images objectAtIndex:0] objectForKey:@"id"] intValue];
                     int plotId = [[plot objectForKey:@"id"] intValue];

                     [[[OTMEnvironment sharedEnvironment] api] getImageForTree:plotId
                                                                       photoId:imageId
                                                                      callback:^(UIImage* image, NSError* error)
                      {
                          self.treeImage.image = image;
                      }];
                 }
             }

             [self setDetailViewData:plot];
             [self slideDetailUpAnimated:YES];

             double lat = [[geom objectForKey:@"lat"] doubleValue];
             double lon = [[geom objectForKey:@"lng"] doubleValue];
             CLLocationCoordinate2D center = CLLocationCoordinate2DMake(lat, lon);
             MKCoordinateSpan span = [[OTMEnvironment sharedEnvironment] mapViewSearchZoomCoordinateSpan];

             [mapView setRegion:MKCoordinateRegionMake(center, span) animated:YES];

             if (self.lastClickedTree) {
                 [mapView removeAnnotation:self.lastClickedTree];
                 self.lastClickedTree = nil;
             }

             self.lastClickedTree = [[MKPointAnnotation alloc] init];

             [self.lastClickedTree setCoordinate:center];

             [mapView addAnnotation:self.lastClickedTree];
             NSLog(@"Here with plot %@", plot);
         }
     }];
}

- (void)fetchAndSetAddTreePlacemarkForCoordinate:(CLLocationCoordinate2D)coordinate
{
    [[[OTMEnvironment sharedEnvironment] api] reverseGeocodeCoordinate:coordinate callback:^(NSArray *placemarks, NSError *error) {
        if (placemarks && [placemarks count] > 0) {
            self.addTreePlacemark = [placemarks objectAtIndex:0];
            NSLog(@"Set add tree placemark to %@", self.addTreePlacemark);
        };
    }];
}

- (void)placeNewTreeAnnotation:(CLLocationCoordinate2D)coordinate
{
    if (!self.addTreeAnnotation) {
        self.addTreeAnnotation = [[MKPointAnnotation alloc] init];
        self.addTreeAnnotation.coordinate = coordinate;
        [self.mapView addAnnotation:self.addTreeAnnotation];
    } else {
        [self slideAddTreeAnnotationToCoordinate:coordinate];
    }
    [self fetchAndSetAddTreePlacemarkForCoordinate:coordinate];
    [self changeMode:Move];
}

#pragma mark UIGestureRecognizer handlers

- (void)handleSingleTapGesture:(UIGestureRecognizer *)gestureRecognizer
{
    if (gestureRecognizer.state != UIGestureRecognizerStateEnded)
    {
        return;
    }

    // If the user taps the map while the searchBar is focused, dismiss the keyboard. This
    // mirrors the behavior of the iOS maps app.
    if ([searchBar isFirstResponder]) {
        [searchBar setShowsCancelButton:NO animated:YES];
        [searchBar resignFirstResponder];
        return;
    }

    CGPoint touchPoint = [gestureRecognizer locationInView:mapView];
    CLLocationCoordinate2D touchMapCoordinate = [mapView convertPoint:touchPoint toCoordinateFromView:mapView];

    if (!mode || mode == Select) {
        [self selectTreeNearCoordinate:touchMapCoordinate];

    } else if (mode == Add) {
        [self placeNewTreeAnnotation:touchMapCoordinate];
        [self changeMode:Move];

    } else if (mode == Move) {
        [self placeNewTreeAnnotation:touchMapCoordinate];
    }

}

#pragma mark UIGestureRecognizerDelegate methods

/**
 Asks the delegate if two gesture recognizers should be allowed to recognize gestures simultaneously.
 */
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)otherGestureRecognizer
{
    // Returning YES ensures that double-tap gestures propogate to the MKMapView
    return YES;
}

#pragma mark MKMapViewDelegate

- (void)mapView:(MKMapView*)mView regionDidChangeAnimated:(BOOL)animated {
    MKCoordinateRegion region = [mView region];

    [(OTMAppDelegate *)[[UIApplication sharedApplication] delegate] setMapRegion:region];

    double lngMin = region.center.longitude - region.span.longitudeDelta / 2.0;
    double lngMax = region.center.longitude + region.span.longitudeDelta / 2.0;
    double latMin = region.center.latitude - region.span.latitudeDelta / 2.0;
    double latMax = region.center.latitude + region.span.latitudeDelta / 2.0;
    
    if (self.lastClickedTree) {
        CLLocationCoordinate2D center = self.lastClickedTree.coordinate;
        
        BOOL shouldBeShown = center.longitude >= lngMin && center.longitude <= lngMax &&
                             center.latitude >= latMin && center.latitude <= latMax;

        if (shouldBeShown && !self.detailsVisible) {
            [self slideDetailUpAnimated:YES];
        } else if (!shouldBeShown && self.detailsVisible) {
            [self slideDetailDownAnimated:YES];
        }
    }
}

- (MKOverlayView *)mapView:(MKMapView *)mapView viewForOverlay:(id <MKOverlay>)overlay
{
    return [[AZPointOffsetOverlay alloc] initWithOverlay:overlay];
}

#define kOTMMapViewAddTreeAnnotationViewReuseIdentifier @"kOTMMapViewAddTreeAnnotationViewReuseIdentifier"

- (MKAnnotationView *)mapView:(MKMapView *)mv viewForAnnotation:(id <MKAnnotation>)annotation
{
    if (annotation == self.addTreeAnnotation) {
        MKAnnotationView *annotationView = [self.mapView dequeueReusableAnnotationViewWithIdentifier:kOTMMapViewAddTreeAnnotationViewReuseIdentifier];
        if (!annotationView) {
            annotationView = [[OTMAddTreeAnnotationView alloc] initWithAnnotation:annotation reuseIdentifier:kOTMMapViewAddTreeAnnotationViewReuseIdentifier];
            ((OTMAddTreeAnnotationView *)annotationView).delegate = self;
            ((OTMAddTreeAnnotationView *)annotationView).mapView = mv;
        }
        return annotationView;
    } else {
        return nil;
    }
}

#pragma mark UISearchBarDelegate methods

- (void)searchBarTextDidBeginEditing:(UISearchBar *)bar {
    [bar setShowsCancelButton:YES animated:YES];
}

- (void)searchBarCancelButtonClicked:(UISearchBar *)bar {
    [bar setText:@""];
    [bar setShowsCancelButton:NO animated:YES];
    [searchBar resignFirstResponder];
}

- (void)searchBarSearchButtonClicked:(UISearchBar *)bar {
    NSString *searchText = [NSString stringWithFormat:@"%@ %@", [bar text], [[OTMEnvironment sharedEnvironment] searchSuffix]];
    [[[OTMEnvironment sharedEnvironment] api] geocodeAddress:searchText
        callback:^(NSArray* matches, NSError* error) {
            if ([matches count] > 0) {
                NSDictionary *firstMatch = [matches objectAtIndex:0];
                double lon = [[firstMatch objectForKey:@"x"] doubleValue];
                double lat = [[firstMatch objectForKey:@"y"] doubleValue];
                CLLocationCoordinate2D center = CLLocationCoordinate2DMake(lat, lon);
                MKCoordinateSpan span = [[OTMEnvironment sharedEnvironment] mapViewSearchZoomCoordinateSpan];
                [mapView setRegion:MKCoordinateRegionMake(center, span) animated:YES];
                [bar setShowsCancelButton:NO animated:YES];
                [bar resignFirstResponder];
            } else {
                NSString *message;
                if (error != nil) {
                    NSLog(@"Error geocoding location: %@", [error description]);
                    message = @"Sorry. There was a problem completing your search.";
                } else {
                    message = @"No Results Found";
                }
                [UIAlertView showAlertWithTitle:nil message:message cancelButtonTitle:@"OK" otherButtonTitle:nil callback:^(UIAlertView *alertView, int btnIdx) {
                    [bar setShowsCancelButton:YES animated:YES];
                    [bar becomeFirstResponder];
                }];
            }
       }];
}

#pragma mark CoreLocation handling

- (IBAction)startFindingLocation:(id)sender
{
    if ([CLLocationManager locationServicesEnabled]) {
        if (nil == [self locationManager]) {
            [self setLocationManager:[[CLLocationManager alloc] init]];
            locationManager.desiredAccuracy = kCLLocationAccuracyHundredMeters;
        }
        // The delegate is cleared in stopFindingLocation so it must be reset here.
        [locationManager setDelegate:self];
        [locationManager startUpdatingLocation];
        NSTimeInterval timeout = [[[OTMEnvironment sharedEnvironment] locationSearchTimeoutInSeconds] doubleValue];
        [self performSelector:@selector(stopFindingLocationAndSetMostAccurateLocation) withObject:nil afterDelay:timeout];
    } else {
        [UIAlertView showAlertWithTitle:nil message:@"Location services are not available." cancelButtonTitle:@"OK" otherButtonTitle:nil callback:nil];
    }
}

- (void)stopFindingLocation {
    [[self locationManager] stopUpdatingLocation];
    // When using the debugger I found that extra events would arrive after calling stopUpdatingLocation.
    // Setting the delegate to nil ensures that those events are not ignored.
    [locationManager setDelegate:nil];
}

- (void)stopFindingLocationAndSetMostAccurateLocation {
    [self stopFindingLocation];
    if ([self mostAccurateLocationResponse] != nil) {
        MKCoordinateSpan span = [[OTMEnvironment sharedEnvironment] mapViewSearchZoomCoordinateSpan];
        [mapView setRegion:MKCoordinateRegionMake([[self mostAccurateLocationResponse] coordinate], span) animated:YES];
    }
    [self setMostAccurateLocationResponse:nil];
}

- (void)locationManager:(CLLocationManager *)manager
    didUpdateToLocation:(CLLocation *)newLocation
           fromLocation:(CLLocation *)oldLocation
{
    NSDate* eventDate = newLocation.timestamp;
    NSTimeInterval howRecent = [eventDate timeIntervalSinceNow];
    // Avoid using any cached location results by making sure they are less than 15 seconds old
    if (abs(howRecent) < 15.0)
    {
        NSLog(@"Location accuracy: horizontal %f, vertical %f", [newLocation horizontalAccuracy], [newLocation verticalAccuracy]);

        if ([self mostAccurateLocationResponse] == nil || [[self mostAccurateLocationResponse] horizontalAccuracy] > [newLocation horizontalAccuracy]) {
            [self setMostAccurateLocationResponse: newLocation];
        }

        if ([newLocation horizontalAccuracy] > 0 && [newLocation horizontalAccuracy] < [manager desiredAccuracy]) {
            [self stopFindingLocation];
            [self setMostAccurateLocationResponse:nil];
            // Cancel the previous performSelector:withObject:afterDelay: - it's no longer necessary
            [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(stopFindingLocation:) object:nil];

            NSLog(@"Found user's location: latitude %+.6f, longitude %+.6f\n",
                  newLocation.coordinate.latitude,
                  newLocation.coordinate.longitude);

            MKCoordinateSpan span = [[OTMEnvironment sharedEnvironment] mapViewSearchZoomCoordinateSpan];
            [mapView setRegion:MKCoordinateRegionMake(newLocation.coordinate, span) animated:YES];
        }
    }
}

#pragma mark OTMAddTreeAnnotationView delegate methods

- (void)movedAnnotation:(MKPointAnnotation *)annotation
{
    [self fetchAndSetAddTreePlacemarkForCoordinate:annotation.coordinate];
}

#pragma mark OTMTreeDetailViewDelegate methods

- (void)viewController:(OTMTreeDetailViewController *)viewController addedTree:(NSDictionary *)details
{
    // TODO: Redraw the tile with the new tree
    [self changeMode:Select];
    [self.navigationController popViewControllerAnimated:YES];
}

@end
