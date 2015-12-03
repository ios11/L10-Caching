//
//  MRCLevelDB.h
//  MRCloudDB
//
//  Created by Osipov on 17.06.14.
//  Copyright (c) 2014 Pavel Osipov. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface MRCLevelDB : NSObject

- (void)openAtPath:(NSString *)path;
- (void)test;

@end
