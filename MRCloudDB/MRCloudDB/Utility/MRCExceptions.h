//
//  MRCExceptions.h
//  MRCloudSDK
//
//  Created by Pavel Osipov on 26.09.12.
//  Copyright (c) 2012 Mail.Ru. All rights reserved.
//

#define MRCThrowDeadlySelectorInvokation(deadlySel, actualSel)                                                                         \
    @throw [NSException exceptionWithName:NSInternalInconsistencyException                                                             \
                                   reason:[NSString stringWithFormat:@"Unexpected deadly selector invokation '%@', use '%@' instead.", \
                                           NSStringFromSelector(deadlySel),                                                            \
                                           NSStringFromSelector(actualSel)]                                                            \
                                 userInfo:nil];

#define MRCThrowNotImplementedException(sel);                                                                                          \
    @throw [NSException exceptionWithName:NSInternalInconsistencyException                                                             \
                                   reason:[NSString stringWithFormat:@"%@ must be overridden iactualSeln a subclass/category.",        \
                                           NSStringFromSelector(sel)]                                                                  \
                                 userInfo:nil];
