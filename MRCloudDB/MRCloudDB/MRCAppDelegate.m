//
//  MRCAppDelegate.m
//  MRCloudDB
//
//  Created by Osipov on 29.06.14.
//  Copyright (c) 2014 Mail.Ru Group. All rights reserved.
//

#import "MRCAppDelegate.h"
#import "MRCNodeLevelDB.h"
#import "MRCNodeSQLDB.h"
#import "MRCNodeLMDB.h"
#import "MRCNode.h"

#import <sys/types.h>
#import <sys/stat.h>

@interface BenchmarkResult : NSObject
@property (nonatomic, assign) CFAbsoluteTime cursorLookupTime;
@property (nonatomic, assign) uint32_t cursorLookupCount;
@property (nonatomic, assign) CFAbsoluteTime nodeLookupTime;
@property (nonatomic, assign) uint32_t nodeLookupCount;
@end

@implementation BenchmarkResult

- (NSString *)description {
    return [NSString stringWithFormat:@"\ncursor lookup {\n    total: %f\n    count: %d\n      avg: %f\n}\nnode lookup {\n    total: %f\n    count: %d\n      avg: %f\n}",
            _cursorLookupTime,
            _cursorLookupCount,
            _cursorLookupTime / (CFAbsoluteTime)_cursorLookupCount,
            _nodeLookupTime,
            _nodeLookupCount,
            _nodeLookupTime / (CFAbsoluteTime)_nodeLookupCount];
}

@end

@interface MRCNode (MRCAppDelegate)
- (BOOL)lookupWithPrefix:(NSString *)prefix
                  nodeDB:(id<MRCNodeDB>)nodeDB
         benchmarkResult:(BenchmarkResult *)benchmarkResult;
@end

@implementation MRCNode (MRCAppDelegate)
- (BOOL)lookupWithPrefix:(NSString *)prefix
                  nodeDB:(id<MRCNodeDB>)nodeDB
         benchmarkResult:(BenchmarkResult *)benchmarkResult {
//    NSLog(@"%@%@", prefix, self);
    return YES;
}
@end

@interface MRCDirectoryNode (MRCAppDelegate)
@end

@implementation MRCDirectoryNode (MRCAppDelegate)

- (BOOL)lookupWithPrefix:(NSString *)prefix
                  nodeDB:(id<MRCNodeDB>)nodeDB
         benchmarkResult:(BenchmarkResult *)benchmarkResult {
    [super lookupWithPrefix:prefix nodeDB:nodeDB benchmarkResult:benchmarkResult];
    NSError *error = nil;
    const CFAbsoluteTime cursorLookupStartTime = CFAbsoluteTimeGetCurrent();
    id<MRCNodeDBCursor> cursor = [nodeDB cursorForDirectory:self
                                                   sortType:MRCNodeDBCursorSortTypeByName
                                                      error:&error];
    const CFAbsoluteTime cursorLookupFinishTime = CFAbsoluteTimeGetCurrent();
    benchmarkResult.cursorLookupTime += (cursorLookupFinishTime - cursorLookupStartTime);
    benchmarkResult.cursorLookupCount += 1;
    if (!cursor) {
        NSLog(@"[ERROR] %@: Failed to get cursor for %@", self, error);
        return NO;
    }
    for (int i = 0; i < cursor.count; ++i) {
        @autoreleasepool {
            const CFAbsoluteTime nodeLookupStartTime = CFAbsoluteTimeGetCurrent();
            MRCNode *node = [cursor fetchNodeAtIndex:i error:&error];
            const CFAbsoluteTime nodeLookupFinishTime = CFAbsoluteTimeGetCurrent();
            benchmarkResult.nodeLookupTime += (nodeLookupFinishTime - nodeLookupStartTime);
            benchmarkResult.nodeLookupCount += 1;
            if (!node) {
                NSLog(@"[ERROR] %@: Failed to fetch node at index %d.", self, i);
                return NO;
            }
            [node lookupWithPrefix:[prefix stringByAppendingString:@"    "]
                            nodeDB:nodeDB
                   benchmarkResult:benchmarkResult];
        }
    }
    return YES;
}

@end

@implementation MRCAppDelegate

- (void)test {
    NSString *nodeDBPath = [self pathForCacheDirectoryWithName:[NSString stringWithFormat:@"tree-3-%llu", (uint64_t)CFAbsoluteTimeGetCurrent()]];
//    NSString *nodeDBPath = [self pathForCacheDirectoryWithName:[NSString stringWithFormat:@"tree-3-441111666"]];
    NSError *error = nil;
    id<MRCNodeDB> nodeDB = [MRCNodeLMDB nodeDBWithPath:nodeDBPath error:&error];
//    id<MRCNodeDB> nodeDB = [MRCNodeSQLDB nodeDBWithPath:nodeDBPath error:&error];
//    id<MRCNodeDB> nodeDB = [MRCNodeLevelDB nodeDBWithPath:nodeDBPath error:&error];
    if (!nodeDB) {
        NSLog(@"[ERROR] Failed to create DB: %@", error);
        return;
    } else {
        NSLog(@"[INFO] DB create at path: %@", nodeDBPath);
    }
    if (![self testNewNodeDB:nodeDB]) {
        return;
    }
//    [self testExistingNodeDB:nodeDB];
}

- (NSMutableArray *)generateTreeForNodeDB:(id<MRCNodeDB>)nodeDB {
    NSMutableArray *tree = [self generateTreeWithDirectoryCount:10
                                                      fileCount:1000
                                                          level:0
                                                       maxLevel:2
                                                    indentation:@"    "];
    const CFAbsoluteTime startTime = CFAbsoluteTimeGetCurrent();
    NSError *error = nil;
    if (![nodeDB replaceNodesInDirectory:[nodeDB rootDirectoryNode]
                               withNodes:tree
                                   error:&error]) {
        NSLog(@"Init failed: %@", error);
        return nil;
    }
    const CFAbsoluteTime finishTime = CFAbsoluteTimeGetCurrent();
    NSLog(@"tree generation time: %f", finishTime - startTime);
    return tree;
}

- (void)updateNodes:(NSArray *)nodes {
    if (!nodes) {
        return;
    }
    
    NSUInteger replacingFileCount = 50;
    NSUInteger replacingDirectoryCount = 4;
    
    NSMutableArray *files = [[nodes filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(MRCNode *node, NSDictionary *bindings) {
        return ![node isDirectory];
    }]] mutableCopy];
    uint64_t now = [[NSDate date] timeIntervalSince1970];
    while (replacingFileCount-- > 0 && [files count] > 0) {
        MRCFileNode *file = files[arc4random() % [files count]];
        file.name = [self generateFileName];
        file.mtime = now - (arc4random() % 100000);
        [files removeObject:file];
    }
    
    NSMutableArray *subdirs = [[nodes filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(MRCNode *node, NSDictionary *bindings) {
        return [node isDirectory];
    }]] mutableCopy];
    while (replacingDirectoryCount-- > 0 && [subdirs count] > 0) {
        MRCDirectoryNode *subdir = subdirs[arc4random() % [subdirs count]];
        subdir.name = [self generateDirectoryName];
        [subdirs removeObject:subdir];
    }
    for (MRCDirectoryNode *subdir in subdirs) {
        [self updateNodes:subdir.children];
    }
}

- (void)testLookupNodeDB:(id<MRCNodeDB>)nodeDB {
    BenchmarkResult *br = [BenchmarkResult new];
    if ([nodeDB.rootDirectoryNode lookupWithPrefix:@"" nodeDB:nodeDB benchmarkResult:br]) {
        NSLog(@"lookup stats: %@", br);
    }
}

- (BOOL)testMergeNodeDB:(id<MRCNodeDB>)nodeDB withTree:(NSArray *)tree {
    const CFAbsoluteTime startTime = CFAbsoluteTimeGetCurrent();
    NSError *error = nil;
    if (![nodeDB replaceNodesInDirectory:[nodeDB rootDirectoryNode]
                               withNodes:tree
                                   error:&error]) {
        NSLog(@"merge failed: %@", error);
        return NO;
    }
    const CFAbsoluteTime finishTime = CFAbsoluteTimeGetCurrent();
    NSLog(@"merge time: %f", finishTime - startTime);
    return YES;
}

- (BOOL)testExistingNodeDB:(id<MRCNodeDB>)nodeDB {
    for (int i = 0; i < 10; ++i) {
        [self testLookupNodeDB:nodeDB];
    }
    return YES;
}

- (BOOL)testNewNodeDB:(id<MRCNodeDB>)nodeDB {
    //
    // GENERATION
    //
    NSArray *tree = [self generateTreeForNodeDB:nodeDB];
    if (!tree) return NO;
    //
    // MERGE
    //
    [self updateNodes:tree];
    if (![self testMergeNodeDB:nodeDB withTree:tree]) return NO;
    //
    // LOOKUP
    //
    [self testLookupNodeDB:nodeDB];
    return YES;
}

- (NSMutableArray *)generateTreeWithDirectoryCount:(uint32_t)directoryCount
                                         fileCount:(uint64_t)fileCount
                                             level:(uint32_t)level
                                          maxLevel:(uint32_t)maxLevel
                                       indentation:(NSString *)indentation {
    NSMutableArray *tree = [NSMutableArray new];
    uint64_t now = [[NSDate date] timeIntervalSince1970];
    for (int i = 0; i < fileCount; ++i) {
        MRCFileNode *file = [MRCFileNode new];
        file.name = [self generateFileName];
        file.mtime = now - (arc4random() % 100000);
        [tree addObject:file];
//        NSLog(@"%@%@", indentation, file);
    }
    if (level < maxLevel) {
        for (int i = 0; i < directoryCount; ++i) {
            MRCDirectoryNode *directory = [MRCDirectoryNode new];
            directory.name = [self generateDirectoryName];
            directory.listingRevision = i;
//            NSLog(@"%@%@", indentation, directory);
            directory.children = [self generateTreeWithDirectoryCount:directoryCount
                                                            fileCount:fileCount
                                                                level:(level + 1)
                                                             maxLevel:maxLevel
                                                          indentation:[indentation stringByAppendingString:@"    "]];
            [tree addObject:directory];
        }
    }
    return tree;
}

- (NSString *)pathForCacheDirectoryWithName:(NSString*)name {
    NSString *cachePath = [NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES) objectAtIndex:0];
    NSError *error = nil;
    BOOL isDirectory = NO;
    if (![[NSFileManager defaultManager] fileExistsAtPath:cachePath isDirectory:&isDirectory] && isDirectory == NO) {
        if (![[NSFileManager defaultManager] createDirectoryAtPath:cachePath
                                      withIntermediateDirectories:NO
                                                       attributes:nil
                                                            error:&error]) {
            @throw [NSException exceptionWithName:NSInternalInconsistencyException
                                           reason:[NSString stringWithFormat:@"Failed to create DB folder with path %@: %@", cachePath, error]
                                         userInfo:nil];
        }
    }
    return [cachePath stringByAppendingPathComponent:name];
}

- (NSString *)generateDirectoryName {
    return [self generateStringWithLength:(arc4random() % 16) + 1];
}

- (NSString *)generateFileName {
    return [NSString stringWithFormat:@"%@.%@", [self generateStringWithLength:(arc4random() % 16) + 1], [self generateStringWithLength:3]];
}

- (NSString *)generateStringWithLength:(NSUInteger)length {
    const char symbols[] = "QAZWSXEDCRFVTGBYHNUJMIKOLP1234567890qazwsxedcrfvtgbyhnujmikolp_";
    NSString *result = [NSString new];
    for (int i = 0; i < length; ++i) {
        result = [result stringByAppendingString:[NSString stringWithFormat:@"%c" , symbols[arc4random() % (sizeof(symbols) - 1)]]];
    }
    return result;
}

#pragma mark - UIApplicationDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions
{
    self.window = [[UIWindow alloc] initWithFrame:[[UIScreen mainScreen] bounds]];
    self.window.rootViewController = [[UIViewController alloc] init];
    self.window.backgroundColor = [UIColor whiteColor];
    [self.window makeKeyAndVisible];
    [self test];
    return YES;
}

- (void)applicationWillResignActive:(UIApplication *)application
{
    // Sent when the application is about to move from active to inactive state. This can occur for certain types of temporary interruptions (such as an incoming phone call or SMS message) or when the user quits the application and it begins the transition to the background state.
    // Use this method to pause ongoing tasks, disable timers, and throttle down OpenGL ES frame rates. Games should use this method to pause the game.
}

- (void)applicationDidEnterBackground:(UIApplication *)application
{
    // Use this method to release shared resources, save user data, invalidate timers, and store enough application state information to restore your application to its current state in case it is terminated later. 
    // If your application supports background execution, this method is called instead of applicationWillTerminate: when the user quits.
}

- (void)applicationWillEnterForeground:(UIApplication *)application
{
    // Called as part of the transition from the background to the inactive state; here you can undo many of the changes made on entering the background.
}

- (void)applicationDidBecomeActive:(UIApplication *)application
{
    // Restart any tasks that were paused (or not yet started) while the application was inactive. If the application was previously in the background, optionally refresh the user interface.
}

- (void)applicationWillTerminate:(UIApplication *)application
{
    // Called when the application is about to terminate. Save data if appropriate. See also applicationDidEnterBackground:.
}

@end
