//
//  STHTTPRequest+STTwitter.m
//  STTwitter
//
//  Created by Nicolas Seriot on 8/6/13.
//  Copyright (c) 2013 Nicolas Seriot. All rights reserved.
//

#import "STHTTPRequest+STTwitter.h"
#import "NSString+STTwitter.h"

#if DEBUG
#   define STLog(...) NSLog(__VA_ARGS__)
#else
#   define STLog(...)
#endif

@implementation STHTTPRequest (STTwitter)

+ (NSError *)errorFromResponseData:(NSData *)responseData {
    // assume error message such as: {"errors":[{"message":"Bad Authentication data","code":215}]}
    
    NSError *jsonError = nil;
    NSDictionary *json = [NSJSONSerialization JSONObjectWithData:responseData options:NSJSONReadingMutableLeaves error:&jsonError];
    if([json isKindOfClass:[NSDictionary class]]) {
        NSArray *errors = [json valueForKey:@"errors"];
        if([errors isKindOfClass:[NSArray class]] && [errors count] > 0) {
            NSDictionary *errorDictionary = [errors lastObject];
            if([errorDictionary isKindOfClass:[NSDictionary class]]) {
                NSString *message = errorDictionary[@"message"];
                NSInteger code = [errorDictionary[@"code"] integerValue];
                NSError *error = [NSError errorWithDomain:NSStringFromClass([self class]) code:code userInfo:@{NSLocalizedDescriptionKey : message}];
                return error;
            }
        }
    }
    
    return nil;
}

+ (STHTTPRequest *)twitterRequestWithURLString:(NSString *)urlString stTwitterProgressBlock:(void(^)(id json))progressBlock stTwitterSuccessBlock:(void(^)(NSDictionary *rateLimits, id json))successBlock stTwitterErrorBlock:(void(^)(NSError *error))errorBlock {
    
    __block STHTTPRequest *r = [self requestWithURLString:urlString];
    __weak STHTTPRequest *wr = r;
    
    r.downloadProgressBlock = ^(NSData *data, NSInteger totalBytesReceived, NSInteger totalBytesExpectedToReceive) {
        
        if(progressBlock == nil) return;
        
        NSError *jsonError = nil;
        id json = [NSJSONSerialization JSONObjectWithData:data options:NSJSONReadingAllowFragments error:&jsonError];
        
        if(json) {
            progressBlock(json);
            return;
        }
        
        // we can receive several dictionaries in the same data chunk
        // such as '{..}\r\n{..}\r\n{..}' which is not valid JSON
        // so we split them up into a 'jsonChunks' array such as [{..},{..},{..}]
        
        NSString *jsonString = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
        
        NSArray *jsonChunks = [jsonString componentsSeparatedByString:@"\r\n"];
        
        for(NSString *jsonChunk in jsonChunks) {
            if([jsonChunk length] == 0) continue;
            NSData *data = [jsonChunk dataUsingEncoding:NSUTF8StringEncoding];
            NSError *jsonError = nil;
            id json = [NSJSONSerialization JSONObjectWithData:data options:NSJSONReadingAllowFragments error:&jsonError];
            if(json == nil) {
                errorBlock(jsonError);
                return;
            }
            progressBlock(json);
        }
    };
    
    r.completionBlock = ^(NSDictionary *headers, NSString *body) {
        
        NSMutableDictionary *rateLimits = [NSMutableDictionary dictionary];
        
        NSString *limit = [headers valueForKey:@"x-ratelimit-limit"];
        NSString *remaining = [headers valueForKey:@"x-ratelimit-remaining"];
        NSString *reset = [headers valueForKey:@"x-ratelimit-reset"];

        if(limit) rateLimits[@"limit"] = limit;
        if(remaining) rateLimits[@"remaining"] = remaining;
        if(reset) rateLimits[@"reset"] = reset;
        
        NSLog(@"-- rateLimits: %@", rateLimits);
        
        /**/
        
        NSError *jsonError = nil;
        id json = [NSJSONSerialization JSONObjectWithData:wr.responseData options:NSJSONReadingMutableLeaves error:&jsonError];
        
        if(json == nil) {
            successBlock(rateLimits, body); // response is not necessarily json
            return;
        }
        
        successBlock(rateLimits, json);
    };
    
    r.errorBlock = ^(NSError *error) {
        
        NSError *e = [self errorFromResponseData:wr.responseData];
        
        if(e) {
            errorBlock(e);
            return;
        }
        
        // do our best to extract Twitter error message from responseString
        
        NSError *regexError = nil;
        NSString *errorString = [wr.responseString firstMatchWithRegex:@"<error>(.*)</error>" error:&regexError];
        if(errorString == nil) {
            STLog(@"-- regexError: %@", [regexError localizedDescription]);
        }
        
        if(errorString) {
            error = [NSError errorWithDomain:NSStringFromClass([self class]) code:0 userInfo:@{NSLocalizedDescriptionKey : errorString}];
        } else if ([wr.responseString length] > 0 && [wr.responseString length] < 64) {
            error = [NSError errorWithDomain:NSStringFromClass([self class]) code:0 userInfo:@{NSLocalizedDescriptionKey : wr.responseString}];
        }
        
        STLog(@"-- body: %@", wr.responseString);
        errorBlock(error);
    };
    
    return r;
}

@end
