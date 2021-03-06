//
//  AppDelegate.m
//  STTwitterRequests
//
//  Created by Nicolas Seriot on 9/5/12.
//  Copyright (c) 2012 Nicolas Seriot. All rights reserved.
//

#import "AppDelegate.h"
#import "STTwitter.h"

@implementation AppDelegate

+ (NSString *)twitterClientInApplicationSupportPath {
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES);
    
    return [[paths lastObject] stringByAppendingPathComponent:@"STTwitter/TwitterClient.plist"];
}

+ (NSArray *)twitterClientsInApplicationSupport {

    NSString *path = [self twitterClientInApplicationSupportPath];
    
    NSArray *a = [NSArray arrayWithContentsOfFile:path];
    
    if(a == nil) {
        NSString *dirPath = [path stringByDeletingLastPathComponent];
        
        NSError *error = nil;
        BOOL dirWasCreated = [[NSFileManager defaultManager] createDirectoryAtPath:dirPath withIntermediateDirectories:YES attributes:nil error:&error];
        if(dirWasCreated == NO) return nil;
        
        NSDictionary *d = @{ @"name":@"- Add your tokens in this file -", @"ck":@"1234", @"cs":@"5678" };
        a = @[d];
        BOOL fileWasCreated = [a writeToFile:path atomically:YES];
        if(fileWasCreated == NO) return nil;
    }

    return a;
}

- (IBAction)editConsumerTokensAction:(id)sender {
    NSString *path = [[self class] twitterClientInApplicationSupportPath];
    
    [[NSWorkspace sharedWorkspace] openFile:path];
}

- (void)awakeFromNib {

    self.twitterClients = [[self class] twitterClientsInApplicationSupport];
    
    self.genericBaseURLString = @"https://api.twitter.com/1.1/";
    self.genericAPIEndpoint = @"statuses/home_timeline.json";
    
    NSMutableDictionary *md = [NSMutableDictionary dictionaryWithObjectsAndKeys:@"count", @"key", @"10", @"value", nil];
    
    self.genericRequestParameters = [ @[md] mutableCopy];
    
    [self changeHTTPMethodAction:self];
    
    if([_twitterClients count]) {
        NSDictionary *firstTwitterClient = [_twitterClients objectAtIndex:0];
        [_twitterClientsController setSelectedObjects:@[firstTwitterClient]];
    }
}

- (IBAction)popupMenuDidSelectTwitterClient:(id)sender {
    NSDictionary *selectedClient = [[_twitterClientsController selectedObjects] lastObject];
    
    BOOL isCustomClient = [[selectedClient valueForKey:@"name"] isEqualToString:@"Custom..."];
    
    _consumerKeyTextField.editable = isCustomClient;
    _consumerSecretTextField.editable = isCustomClient;
    
    _consumerKeyTextField.stringValue = [selectedClient valueForKey:@"ck"];
    _consumerSecretTextField.stringValue = [selectedClient valueForKey:@"cs"];
}

- (void)askForUsernameAndPasswordWithCompletionBlock:(UsernamePasswordBlock_t)completionBlock {
    self.pinGuessLoginCompletionBlock = completionBlock;
    
    NSAlert *alert = [[NSAlert alloc] init];
    [alert addButtonWithTitle:@"Login"];
    [alert addButtonWithTitle:@"Cancel"];
    [alert setMessageText:@"Please enter username and password:"];
    [alert setInformativeText:@"STTwitter will login on Twitter through the website and parse the HTML to guess the PIN."];
    [alert setAlertStyle:NSInformationalAlertStyle];
    
    NSTextField *usernameTextField = [[NSTextField alloc] initWithFrame:NSMakeRect(0,32, 180, 24)];
    NSSecureTextField *passwordTextField = [[NSSecureTextField alloc] initWithFrame:NSMakeRect(0, 0, 180, 24)];
    
    NSView *accessoryView = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 200, 64)];
    [accessoryView addSubview:usernameTextField];
    [accessoryView addSubview:passwordTextField];
    
    [alert setAccessoryView:accessoryView];
    
    [alert beginSheetModalForWindow:_window modalDelegate:self didEndSelector:@selector(alertDidEnd:returnCode:contextInfo:) contextInfo:nil];
}

- (void)alertDidEnd:(NSAlert *)alert returnCode:(NSInteger)returnCode contextInfo:(NSDictionary *)contextInfo {
    if(returnCode != NSAlertFirstButtonReturn) return;
    
    NSArray *subviews = [alert.accessoryView subviews];
    
    NSTextField *usernameTextField = [subviews objectAtIndex:0];
    NSSecureTextField *passwordTextField = [subviews objectAtIndex:1];
    
    NSString *username = [usernameTextField stringValue];
    NSString *password = [passwordTextField stringValue];
    
    _pinGuessLoginCompletionBlock(username, password);
}

// OS X Twitter account
- (IBAction)loginOSX:(id)sender {
    self.twitter = [STTwitterAPI twitterAPIOSWithFirstAccount];
    
    self.osxStatus = @"-";
    
    [_twitter verifyCredentialsWithSuccessBlock:^(NSString *username) {
        self.osxStatus = [NSString stringWithFormat:@"Access granted for %@", username];
    } errorBlock:^(NSError *error) {
        self.osxStatus = [error localizedDescription];
    }];
}

// OAuth - PIN
- (IBAction)fetchPIN:(id)sender {
    
    self.pinURL = nil;
    self.pinGuessLoginCompletionBlock = nil;
    
    self.pinStatus1 = @"-";
    self.pinStatus2 = @"-";
    
    self.twitter = [STTwitterAPI twitterAPIWithOAuthConsumerName:nil
                                                     consumerKey:_consumerKeyTextField.stringValue
                                                  consumerSecret:_consumerSecretTextField.stringValue];
    
    [_twitter postTokenRequest:^(NSURL *url, NSString *oauthToken) {
        self.pinURL = url;
        
        self.pinStatus1 = [url description];
        
    } oauthCallback:_oauthCallback
                    errorBlock:^(NSError *error) {
                        
                        self.pinStatus1 = [error localizedDescription];
                    }];
}

- (IBAction)openURL:(id)sender {
    [[NSWorkspace sharedWorkspace] openURL:_pinURL];
}

- (IBAction)guessPIN:(id)sender {
    
    self.pin = @"";
    self.pinStatus2 = @"";
    
    STTwitterHTML *twitterHTML = [[STTwitterHTML alloc] init];
    
    [_twitter postTokenRequest:^(NSURL *pinURL, NSString *oauthToken) {
        
        [twitterHTML getLoginForm:^(NSString *authenticityToken) {
            
            [self askForUsernameAndPasswordWithCompletionBlock:^(NSString *username, NSString *password) {
                
                [twitterHTML postLoginFormWithUsername:username password:password authenticityToken:authenticityToken successBlock:^{
                    
                    [twitterHTML getAuthorizeFormAtURL:pinURL successBlock:^(NSString *newAuthenticityToken, NSString *newOauthToken) {
                        
                        [twitterHTML postAuthorizeFormResultsAtURL:pinURL authenticityToken:newAuthenticityToken oauthToken:newOauthToken successBlock:^(NSString *PIN) {
                            
                            self.pin = PIN;
                            
                        } errorBlock:^(NSError *error) {
                            self.pinStatus2 = [error localizedDescription];
                        }];
                        
                    } errorBlock:^(NSError *error) {
                        self.pinStatus2 = [error localizedDescription];
                    }];
                    
                } errorBlock:^(NSError *error) {
                    self.pinStatus2 = [error localizedDescription];
                }];
                
            }];
            
        } errorBlock:^(NSError *error) {
            self.pinStatus2 = [error localizedDescription];
        }];
        
    } oauthCallback:nil
                    errorBlock:^(NSError *error) {
                        self.pinStatus2 = [error localizedDescription];
                    }];
    
}

- (IBAction)loginPIN:(id)sender {
    
    self.pinStatus2 = @"";
    self.pinOAuthToken = @"";
    self.pinOAuthTokenSecret = @"";
    
    [_twitter postAccessTokenRequestWithPIN:_pin
                               successBlock:^(NSString *oauthToken, NSString *oauthTokenSecret, NSString *userID, NSString *screenName) {
                                   
                                   self.pinStatus2 = [NSString stringWithFormat:@"Access granted for %@", screenName];
                                   
                                   self.pinOAuthToken = oauthToken;
                                   self.pinOAuthTokenSecret = oauthTokenSecret;
                                   
                               } errorBlock:^(NSError *error) {
                                   self.pinStatus2 = [error localizedDescription];
                               }];
}

//- (void)setXAuthPassword:(NSString *)s {
//    _xAuthPassword = s;
//}

// OAuth - XAuth
- (IBAction)loginXAuth:(id)sender {
    
    self.xAuthStatus = @"-";
    self.xAuthOAuthToken = @"";
    self.xAuthOAuthTokenSecret = @"";
    
    NSAssert(_xAuthUsername, @"");
    NSAssert(_xAuthPassword, @"");
    
    self.twitter = [STTwitterAPI twitterAPIWithOAuthConsumerName:nil
                                                     consumerKey:_consumerKeyTextField.stringValue
                                                  consumerSecret:_consumerSecretTextField.stringValue
                                                        username:_xAuthUsername
                                                        password:_xAuthPassword];
    
    [_twitter verifyCredentialsWithSuccessBlock:^(NSString *username) {
        
        self.xAuthStatus = [NSString stringWithFormat:@"Access granted for %@", username];
        
        self.xAuthOAuthToken = _twitter.oauthAccessToken;
        self.xAuthOAuthTokenSecret = _twitter.oauthAccessTokenSecret;
        
    } errorBlock:^(NSError *error) {
        
        self.xAuthStatus = [error localizedDescription];
    }];
}

// Application Only
- (IBAction)fetchBearer:(id)sender {
    
    self.bearerStatus = @"-";
    
    self.twitter = [STTwitterAPI twitterAPIAppOnlyWithConsumerKey:_consumerKeyTextField.stringValue consumerSecret:_consumerSecretTextField.stringValue];
    
    [_twitter verifyCredentialsWithSuccessBlock:^(NSString *bearerToken) {
        self.bearerToken = [_twitter bearerToken];
    } errorBlock:^(NSError *error) {
        self.bearerToken = [_twitter bearerToken];
        self.bearerStatus = [error localizedDescription];
    }];
}

- (IBAction)invalidateBearer:(id)sender {
    
    self.bearerStatus = @"-";
    
    [_twitter invalidateBearerTokenWithSuccessBlock:^() {
        self.bearerToken = [_twitter bearerToken];
        self.bearerStatus = @"ok";
    } errorBlock:^(NSError *error) {
        self.bearerToken = [_twitter bearerToken];
        self.bearerStatus = [error localizedDescription];
    }];
}

// OAuth - Tokens
- (IBAction)loginTokens:(id)sender {
    
    self.oauthTokensStatus = @"-";
    
    self.twitter = [STTwitterAPI twitterAPIWithOAuthConsumerName:nil
                                                     consumerKey:_consumerKeyTextField.stringValue
                                                  consumerSecret:_consumerSecretTextField.stringValue
                                                      oauthToken:_oauthToken
                                                oauthTokenSecret:_oauthTokenSecret];
    
    [_twitter verifyCredentialsWithSuccessBlock:^(NSString *username) {
        
        self.oauthTokensStatus = [NSString stringWithFormat:@"Access granted for %@", username];
        
        self.oauthToken = _twitter.oauthAccessToken;
        self.oauthTokenSecret = _twitter.oauthAccessTokenSecret;
        
    } errorBlock:^(NSError *error) {
        
        self.oauthTokensStatus = [error localizedDescription];
    }];
}

- (IBAction)getTimeline:(id)sender {
    
    self.twitterGetTimelineStatus = @"-";
    self.timelineStatuses = [NSArray array];
    
    if([_twitterTimelineUsername length] > 0) {
        [_twitter getUserTimelineWithScreenName:_twitterTimelineUsername successBlock:^(NSArray *statuses) {
            self.timelineStatuses = statuses;
            self.twitterGetTimelineStatus = @"OK";
        } errorBlock:^(NSError *error) {
            self.twitterGetTimelineStatus = error ? [error localizedDescription] : @"Unknown error";
        }];
    } else {
        [_twitter getHomeTimelineSinceID:nil count:20 successBlock:^(NSArray *statuses) {
            self.timelineStatuses = statuses;
            self.twitterGetTimelineStatus = @"OK";
        } errorBlock:^(NSError *error) {
            self.twitterGetTimelineStatus = error ? [error localizedDescription] : @"Unknown error";
        }];
    }
}

- (IBAction)chooseMedia:(id)sender {
    self.twitterPostMediaURL = nil;
    
    NSOpenPanel *panel = [NSOpenPanel openPanel];
    
    [panel setCanChooseDirectories:NO];
    [panel setCanChooseFiles:YES];
    [panel setAllowedFileTypes:@[ @"png", @"PNG", @"jpg", @"JPG", @"jpeg", @"JPEG", @"gif", @"GIF"] ];
    
    [panel beginSheetModalForWindow:self.window completionHandler:^(NSInteger result) {
        
        if (result != NSFileHandlingPanelOKButton) return;
        
        NSArray *urls = [panel URLs];
        
        NSPredicate *p = [NSPredicate predicateWithBlock:^BOOL(id evaluatedObject, NSDictionary *bindings) {
            if([evaluatedObject isKindOfClass:[NSURL class]] == NO) return NO;
            
            NSURL *url = (NSURL *)evaluatedObject;
            
            return [url isFileURL];
        }];
        
        NSArray *fileURLS = [urls filteredArrayUsingPredicate:p];
        
        NSURL *fileURL = [fileURLS lastObject];
        
        BOOL isDir = NO;
        if ([[NSFileManager defaultManager] fileExistsAtPath: fileURL.path isDirectory: &isDir] == NO) return;
        
        self.twitterPostMediaURL = fileURL;
    }];
}

- (IBAction)postTweet:(id)sender {
    
    self.twitterPostTweetStatus = @"-";
    
    if(_twitterPostMediaURL) {
        
        [_twitter postStatusUpdate:_twitterPostTweetText
                 inReplyToStatusID:nil
                          mediaURL:_twitterPostMediaURL
                           placeID:nil
                          latitude:_twitterPostLatitude
                         longitude:_twitterPostLongitude
                      successBlock:^(NSDictionary *status) {
                          
                          self.twitterPostTweetText = @"";
                          self.twitterPostTweetStatus = @"OK";
                          self.twitterPostLatitude = nil;
                          self.twitterPostLongitude = nil;
                          self.twitterPostMediaURL = nil;
                      } errorBlock:^(NSError *error) {
                          self.twitterPostTweetStatus = error ? [error localizedDescription] : @"Unknown error";
                      }];
        
    } else {
        
        [_twitter postStatusUpdate:_twitterPostTweetText
                 inReplyToStatusID:nil
                          latitude:_twitterPostLatitude
                         longitude:_twitterPostLongitude
                           placeID:nil
                displayCoordinates:@(YES)
                          trimUser:nil
                      successBlock:^(NSDictionary *status) {
                          
                          self.twitterPostTweetText = @"";
                          self.twitterPostTweetStatus = @"OK";
                          self.twitterPostLatitude = nil;
                          self.twitterPostLongitude = nil;
                          self.twitterPostMediaURL = nil;
                      } errorBlock:^(NSError *error) {
                          self.twitterPostTweetStatus = error ? [error localizedDescription] : @"Unknown error";
                      }];
    }
}

- (IBAction)changeHTTPMethodAction:(id)sender {
    self.genericHTTPMethod = [_genericHTTPMethodPopUpButton titleOfSelectedItem];
    NSLog(@"-- %s", __PRETTY_FUNCTION__);
    NSLog(@"-- %@", _genericHTTPMethod);
}

- (IBAction)sendRequestAction:(id)sender {
    NSLog(@"-- %s", __PRETTY_FUNCTION__);
    
    NSAssert(_genericAPIEndpoint, @"");
    NSAssert(_genericHTTPMethod, @"");
    NSAssert(_genericBaseURLString, @"");
    
    NSDictionary *attributes = @{ NSFontAttributeName : [NSFont fontWithName:@"Menlo" size:12] };
    
    NSMutableDictionary *parameters = [NSMutableDictionary dictionaryWithCapacity:[_genericRequestParameters count]];
    
    for(NSDictionary *d in _genericRequestParameters) {
        NSString *k = d[@"key"];
        NSString *v = d[@"value"];
        [parameters setObject:v forKey:k];
    }
    
    self.genericTextViewAttributedString = [[NSAttributedString alloc] initWithString:@"" attributes:attributes];
    
    [_twitter fetchResource:_genericAPIEndpoint HTTPMethod:_genericHTTPMethod baseURLString:_genericBaseURLString parameters:parameters progressBlock:nil successBlock:^(NSString *requestID, NSDictionary *rateLimits, id response) {
        NSString *s = [response description];
        self.genericTextViewAttributedString = [[NSAttributedString alloc] initWithString:s attributes:attributes];;
    } errorBlock:^(NSString *requestID, NSError *error) {
        NSString *s = @"error";
        if(error) {
            s = [error localizedDescription];
        }
        self.genericTextViewAttributedString = [[NSAttributedString alloc] initWithString:s attributes:attributes];
    }];
}

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification {
    // ...
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)theApplication {
    return YES;
}

@end
