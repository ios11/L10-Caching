//
//  NSBundle+MRCSDK.m
//  MRCloudSDK
//
//  Created by Osipov on 30.10.13.
//  Copyright (c) 2013 Mail.Ru Group. All rights reserved.
//

#import "NSBundle+MRCSDK.h"
#import "MRCAppDelegate.h"

@implementation NSBundle (MRCSDK)

+ (NSBundle *)mrc_SDKBundle {
    static dispatch_once_t onceToken;
    static NSBundle *bundle = nil;
    dispatch_once(&onceToken, ^{
        bundle = [NSBundle bundleForClass:[MRCAppDelegate class]];
    });
    return bundle;
}

@end
