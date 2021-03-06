// PluginWindowController.m
// 
// Copyright (c) 2013 Marin Usalj | mneorr.com
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
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

#import "ATZPluginWindowController.h"
#import "ATZDownloader.h"
#import "ATZPackageFactory.h"

#import "ATZPlugin.h"
#import "ATZColorScheme.h"
#import "ATZTemplate.h"

static NSString *const ALL_ITEMS_ID = @"AllItemsToolbarItem";
static NSString *const CLASS_PREDICATE_FORMAT = @"(self isKindOfClass: %@)";
static NSString *const SEARCH_PREDICATE_FORMAT = @"(name contains[cd] %@ OR description contains[cd] %@)";
static NSString *const SEARCH_AND_CLASS_PREDICATE_FORMAT = @"(name contains[cd] %@ OR description contains[cd] %@) AND (self isKindOfClass: %@)";

@interface ATZPluginWindowController ()
@property (nonatomic) Class selectedPackageClass;
@end

@implementation ATZPluginWindowController

- (id)init {
    if (self = [super init]) {
        self.filterPredicate = [NSPredicate predicateWithValue:YES];
        @try { [self fetchPlugins]; [self updateAlcatraz]; }
        @catch(NSException *exception) { NSLog(@"I've heard you like exceptions... %@", exception); }
    }
    return self;
}

- (void)dealloc {
    [self.packages release];
    [self.filterPredicate release];
    [super dealloc];
}

- (void)windowDidLoad {
    [[self.window toolbar] setSelectedItemIdentifier:ALL_ITEMS_ID];
}

#pragma mark - Bindings

- (IBAction)checkboxPressed:(NSButton *)checkbox {
    ATZPackage *package = [self.packages filteredArrayUsingPredicate:self.filterPredicate][[self.tableView rowForView:checkbox]];
    
    if (package.isInstalled)
        [self removePackage:package andUpdateCheckbox:checkbox];
    else
        [self installPackage:package andUpdateCheckbox:checkbox];
}

- (IBAction)showAllPackages:(id)sender {
    self.selectedPackageClass = nil;
    [self updatePredicate];
}

- (IBAction)showOnlyPlugins:(id)sender {
    self.selectedPackageClass = [ATZPlugin class];
    [self updatePredicate];
}

- (IBAction)showOnlyColorSchemes:(id)sender {
    self.selectedPackageClass = [ATZColorScheme class];
    [self updatePredicate];
}

- (IBAction)showOnlyTemplates:(id)sender {
    self.selectedPackageClass = [ATZTemplate class];
    [self updatePredicate];
}

- (void)controlTextDidChange:(NSNotification *)note {
    [self updatePredicate];
}

#pragma mark - Private

- (void)removePackage:(ATZPackage *)package andUpdateCheckbox:(NSButton *)checkbox {
    [self showInstallationIndicators];
    
    [package removeWithCompletion:^(NSError *failure) {

        NSString *message = failure ? [NSString stringWithFormat:@"%@ failed to uninstall :(", package.name] :
                                      [NSString stringWithFormat:@"%@ uninstalled.", package.name];

        [[self statusLabel] setStringValue:message];
        [self reloadUIForPackage:package fromCheckbox:checkbox];
    }];
}

- (void)installPackage:(ATZPackage *)package andUpdateCheckbox:(NSButton *)checkbox {
    [self showInstallationIndicators];
    [package installWithProgressMessage:^(NSString *progressMessage) { self.statusLabel.stringValue = progressMessage; }
                             completion:^(NSError *failure) {
        
        NSString *message = failure ? [NSString stringWithFormat:@"%@ failed to install :( Error: %@", package.name, failure.description] :
                                      [NSString stringWithFormat:@"%@ installed.", package.name];

        [[self statusLabel] setStringValue:message];
        [self reloadUIForPackage:package fromCheckbox:checkbox];
    }];
}

- (void)reloadUIForPackage:(ATZPackage *)package fromCheckbox:(NSButton *)checkbox {
    [self hideInstallationIndicators];
    [self reloadCheckbox:checkbox];
    if (package.requiresRestart) [self.restartLabel setHidden:NO];
}

- (void)hideInstallationIndicators {
    [[self progressIndicator] stopAnimation:nil];
    [[self progressIndicator] setHidden:YES];
}

- (void)showInstallationIndicators {
    [[self progressIndicator] setHidden:NO];
    [[self progressIndicator] startAnimation:nil];
}

- (void)reloadCheckbox:(NSButton *)checkbox {
    [self.tableView reloadDataForRowIndexes:[NSIndexSet indexSetWithIndex:[self.tableView rowForView:checkbox]]
                              columnIndexes:[NSIndexSet indexSetWithIndex:0]];
}

- (void)updatePredicate {
    NSString *searchText = self.searchField.stringValue;    
    // filter by type and search field text
    if (self.selectedPackageClass && searchText.length > 0) {
        self.filterPredicate = [NSPredicate predicateWithFormat:SEARCH_AND_CLASS_PREDICATE_FORMAT, searchText, searchText, self.selectedPackageClass];
        
    // filter by type
    } else if (self.selectedPackageClass) {
        self.filterPredicate = [NSPredicate predicateWithFormat:CLASS_PREDICATE_FORMAT, self.selectedPackageClass];
        
    // filter by search field text
    } else if (searchText.length > 0) {
        self.filterPredicate = [NSPredicate predicateWithFormat:SEARCH_PREDICATE_FORMAT, searchText, searchText];
        
    // show all
    } else {
        self.filterPredicate = [NSPredicate predicateWithValue:YES];
    }
}

- (void)fetchPlugins {
    @autoreleasepool {
        ATZDownloader *downloader = [ATZDownloader new];
        [downloader downloadPackageListWithCompletion:^(NSDictionary *packageList, NSError *error) {
            
            if (error)
                NSLog(@"Error while downloading packages! %@", error);
            else
                self.packages = [ATZPackageFactory createPackagesFromDicts:packageList];
            
            [downloader release];
        }];
    }
}

- (void)updateAlcatraz {
    NSOperationQueue *queue = [[NSOperationQueue alloc] init];
    [queue addOperationWithBlock:^{
        [self downloadAndInstallAlcatraz];
        [queue release];
    }];
}

- (void)downloadAndInstallAlcatraz {
    ATZPlugin *alcatraz = [[ATZPlugin alloc] initWithDictionary:@{
                           @"name": @"Alcatraz",
                           @"url": @"https://github.com/mneorr/Alcatraz",
                           @"description": @"Self updating installer"
                           }];
    [alcatraz installWithProgressMessage:^(NSString *proggressMessage) {
        
    } completion:^(NSError *failure) {
        if (failure)
            NSLog(@"\n\nUpdating alcatraz failed! %@\n\n", failure);
        else
            NSLog(@"Alcatraz updated!");
        
        [alcatraz release];
    }];
}

@end
