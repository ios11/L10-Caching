//
//  MRCDefaultErrorHandler.m
//  MRCloudDB
//
//  Created by Osipov on 29.06.14.
//  Copyright (c) 2014 Mail.Ru Group. All rights reserved.
//

#import "MRCDefaultErrorHandler.h"

@implementation MRCDefaultErrorHandler

- (void)handleError:(NSError *)error {
    NSLog(@"[ERROR]: %@ (%@)", [error localizedDescription], error);
}

@end
