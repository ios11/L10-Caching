//
//  MRCErrorHandler.h
//  MRCloudSDK
//
//  Created by Pavel Osipov on 11.02.14.
//  Copyright (c) 2014 Mail.Ru Group. All rights reserved.
//

#import <Foundation/Foundation.h>

@protocol MRCErrorHandler <NSObject>

- (void)handleError:(NSError *)error;

@end
