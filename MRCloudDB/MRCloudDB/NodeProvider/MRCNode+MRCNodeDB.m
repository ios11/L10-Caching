//
//  MRCNode+MRCNodeDB.m
//  MRCloudDB
//
//  Created by Osipov on 12.09.14.
//  Copyright (c) 2014 Mail.Ru Group. All rights reserved.
//

#import "MRCNode+MRCNodeDB.h"
#import <objc/runtime.h>

static char kNodeID;

@implementation MRCNode (MRCNodeDB)
@dynamic ID;

- (NSNumber *)ID {
    return objc_getAssociatedObject(self, &kNodeID);
}

- (void)setID:(NSNumber *)ID {
    objc_setAssociatedObject(self, &kNodeID, ID, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

@end
