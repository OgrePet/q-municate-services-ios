//
//  QMDBStorage.m
//  QMDBStorage
//
//  Created by Andrey on 06.11.14.
//  Copyright (c) 2015 Quickblox Team. All rights reserved.
//

#import "QMDBStorage.h"

static id<QMCDRecordStackFactory> stackFactory = nil;

@interface QMDBStorage ()

#define QM_LOGGING_ENABLED 1

@property (strong, nonatomic) dispatch_queue_t queue;
@property (strong, nonatomic) QMCDRecordStack *stack;
@property (strong, nonatomic) NSManagedObjectContext *bgContex;

@end

@implementation QMDBStorage

+ (void) registerQMCDRecordStackFactory: (id<QMCDRecordStackFactory>) newStackFactory
{
    stackFactory = newStackFactory;
}

- (instancetype)initWithStoreNamed:(NSString *)storeName model:(NSManagedObjectModel *)model queueLabel:(const char *)queueLabel {
    
    self = [self init];
    if (self) {
        
        self.queue = dispatch_queue_create(queueLabel, DISPATCH_QUEUE_SERIAL);
        //Create Chat coredata stack
        
        if (stackFactory) {
            self.stack = [stackFactory createStackWithStoreName: storeName model: model];
        }
        else {
            self.stack = [AutoMigratingQMCDRecordStack stackWithStoreNamed:storeName model:model];
        }
		[QMCDRecordStack setDefaultStack:self.stack];
    }
    
    return self;
}

+ (void)setupDBWithStoreNamed:(NSString *)storeName {
    
    NSAssert(nil, @"must be overloaded");
}

+ (void)cleanDBWithStoreName:(NSString *)name {
    
    NSURL *storeUrl = [NSPersistentStore QM_fileURLForStoreName:name];
    
    
    if (storeUrl) {
    
        [NSPersistentStore QM_removePersistentStoreFilesAtURL: storeUrl];
    }
}

- (NSManagedObjectContext *)bgContex {
    
    if (!_bgContex) {
        _bgContex = [NSManagedObjectContext QM_confinementContextWithParent:self.stack.context];
    }
    
    return _bgContex;
}

- (void)async:(void(^)(NSManagedObjectContext *context))block {
    
    dispatch_async(self.queue, ^{
        block(self.bgContex);
    });
}

- (void)sync:(void(^)(NSManagedObjectContext *context))block {
    
    dispatch_sync(self.queue, ^{
        block(self.bgContex);
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
