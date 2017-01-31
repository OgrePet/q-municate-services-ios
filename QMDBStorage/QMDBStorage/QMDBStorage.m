//
//  QMDBStorage.m
//  QMDBStorage
//
//  Created by Andrey on 06.11.14.
//  Copyright (c) 2015 Quickblox Team. All rights reserved.
//

#import "QMDBStorage.h"
#import "QMSLog.h"

static id<QMCDRecordStackFactory> stackFactory = nil;

@interface QMDBStorage ()

#define QM_LOGGING_ENABLED 1

@property (strong, nonatomic) dispatch_queue_t queue;
@property (strong, nonatomic) QMCDRecordStack *stack;
@property (strong, nonatomic) NSManagedObjectContext *bgContext;

@end

@implementation QMDBStorage

+ (void) registerQMCDRecordStackFactory: (id<QMCDRecordStackFactory>) newStackFactory
{
    stackFactory = newStackFactory;
}

- (instancetype)initWithStoreNamed:(NSString *)storeName
                             model:(NSManagedObjectModel *)model
                        queueLabel:(const char *)queueLabel {
    
    return [self initWithStoreNamed: storeName
                              model: model
                      storePassword: nil
                         queueLabel: queueLabel
         applicationGroupIdentifier: nil];
}

- (instancetype)initWithStoreNamed:(NSString *)storeName
                             model:(NSManagedObjectModel *)model
                     storePassword:(NSString*) storePassword
                        queueLabel:(const char *)queueLabel {
    
    return [self initWithStoreNamed: storeName
                              model: model
                      storePassword: storePassword
                         queueLabel: queueLabel
         applicationGroupIdentifier: nil];
}

- (instancetype)initWithStoreNamed:(NSString *)storeName
                             model:(NSManagedObjectModel *)model
                        queueLabel:(const char *)queueLabel
        applicationGroupIdentifier:(NSString *)appGroupIdentifier
{
    return [self initWithStoreNamed: storeName
                              model: model
                      storePassword: nil
                         queueLabel: queueLabel
         applicationGroupIdentifier: appGroupIdentifier];
}


- (instancetype)initWithStoreNamed:(NSString *)storeName
                             model:(NSManagedObjectModel *)model
                     storePassword:(NSString*) storePassword
                        queueLabel:(const char *)queueLabel 
	    applicationGroupIdentifier:(NSString *)appGroupIdentifier {

    self = [self init];
    if (self) {
        
        self.queue = dispatch_queue_create(queueLabel, DISPATCH_QUEUE_SERIAL);
        //Create Chat coredata stack
        
        if (stackFactory && storePassword) {
            self.stack = [stackFactory createStackWithStoreName: storeName storePassword: storePassword model: model];
        }
        else {
            self.stack = [AutoMigratingQMCDRecordStack stackWithStoreNamed:storeName model:model applicationGroupIdentifier:appGroupIdentifier];
        }
        [QMCDRecordStack setDefaultStack:self.stack];
    }

    return self;
}

+ (void)setupDBWithStoreNamed:(NSString *)storeName {
    
    NSAssert(nil, @"must be overloaded");
}

+ (void)setupDBWithStoreNamed:(NSString *)storeName withPassword: (NSString*) storePassword
{
    NSAssert(nil, @"must be overloaded");
}

+ (void)cleanDBWithStoreName:(NSString *)name {
    
    [self cleanDBWithStoreName:name applicationGroupIdentifier:nil];
}

+ (void)cleanDBWithStoreName:(NSString *)name applicationGroupIdentifier:(NSString *)appGroupIdentifier {
    
    NSURL *storeUrl = [NSPersistentStore QM_fileURLForStoreNameIfExistsOnDisk:name applicationGroupIdentifier:appGroupIdentifier];
    
    if (storeUrl) {
    
        [NSPersistentStore QM_removePersistentStoreFilesAtURL: storeUrl];
    }
}

- (NSManagedObjectContext *)bgContext {
    
    if (!_bgContext) {
        NSManagedObjectContext *context = [NSManagedObjectContext QM_context];
        [context setParentContext:self.stack.context];
        
        _bgContext = context;
    }
    
    return _bgContext;
}

- (void)async:(void(^)(NSManagedObjectContext *context))block {
    
    dispatch_async(self.queue, ^{
        block(self.bgContext);
    });
}

- (void)sync:(void(^)(NSManagedObjectContext *context))block {
    
    dispatch_sync(self.queue, ^{
        block(self.bgContext);
    });
}

- (void)save:(dispatch_block_t)completion {
    
    [self async:^(NSManagedObjectContext *context) {
        
        [context QM_saveToPersistentStoreAndWait];
        
        if (completion) {
            DO_AT_MAIN(completion());
        }
    }];
}

@end
