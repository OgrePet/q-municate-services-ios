//
//  QMServiceManager.m
//  QMServices
//
//  Created by Andrey Moskvin on 5/19/15.
//  Copyright (c) 2015 Quickblox Team. All rights reserved.
//

#import "QMServicesManager.h"
#import "_CDMessage.h"
#import "_CDDialog.h"

@interface QMServicesManager ()
{
    BOOL isCachesCreated;
}

@property (nonatomic, strong) QMAuthService* authService;
@property (nonatomic, strong) QMChatService* chatService;

/**
 *  Logout group for synchronous completion.
 */
@property (nonatomic, strong) dispatch_group_t logoutGroup;

@end

@implementation QMServicesManager

- (instancetype)init {
	self = [super init];
	if (self) {
		_authService = [[QMAuthService alloc] initWithServiceManager:self];
		_chatService = [[QMChatService alloc] initWithServiceManager:self cacheDataSource:self];
        [_chatService setChatMessagesPerPage:kQMChatMessagesPerPage];
        [_chatService addDelegate:self];
        
        _usersService = [[QMUsersService alloc] initWithServiceManager:self cacheDataSource:self];
        [_usersService addDelegate:self];

        // Enables auto join handling for group chat dialogs.
        // Remove this or set it to NO if you want to handle group chat dialog joining manually
        // or you are using our Enterprise feature to manage group chat dialogs without join being required.
        _chatService.enableAutoJoin = YES;
        
        _logoutGroup = dispatch_group_create();
	}
	return self;
}

+ (instancetype)instance {
	static QMServicesManager* manager = nil;
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		manager = [[self alloc] init];
	});
	return manager;
}

- (void)logoutWithCompletion:(dispatch_block_t)completion
{
    if ([QBSession currentSession].currentUser != nil) {
        __weak typeof(self)weakSelf = self;    
        
        dispatch_group_enter(self.logoutGroup);
        [self.authService logOut:^(QBResponse *response) {
            __typeof(self) strongSelf = weakSelf;
            [strongSelf.chatService disconnectWithCompletionBlock:nil];
            [strongSelf.chatService free];
            dispatch_group_leave(strongSelf.logoutGroup);
        }];
        
        dispatch_group_enter(self.logoutGroup);
        [[QMChatCache instance] deleteAllDialogs:^{
            __typeof(self) strongSelf = weakSelf;
            dispatch_group_leave(strongSelf.logoutGroup);
        }];
        
        dispatch_group_enter(self.logoutGroup);
        [[QMChatCache instance] deleteAllMessages:^{
            __typeof(self) strongSelf = weakSelf;
            dispatch_group_leave(strongSelf.logoutGroup);
        }];
        
        dispatch_group_notify(self.logoutGroup, dispatch_get_main_queue(), ^{
            __typeof(self) strongSelf = weakSelf;
            [strongSelf cleanCaches];
            if (completion) {
                completion();
            }
        });
    } else {
        [self cleanCaches];
        if (completion) {
            completion();
        }
    }
}

- (void)logInWithUser:(QBUUser *)user
		   completion:(void (^)(BOOL success, NSString *errorMessage))completion
{
    
    __weak typeof(self)weakSelf = self;
	[self.authService logInWithUser:user completion:^(QBResponse *response, QBUUser *userProfile) {
		if (response.error != nil) {
            
                [self createCachesWithPassword:user.password];
                [self.chatService loadCachedDialogsWithCompletion: nil];
            
			if (completion != nil) {
				completion(NO, response.error.error.localizedDescription);
			}
			return;
		}
        
        [self createCachesWithPassword:user.password];
        [self.chatService loadCachedDialogsWithCompletion: nil];

        [weakSelf.chatService connectWithCompletionBlock:^(NSError *error) {
            //
            if (completion != nil) {
                completion(error == nil, error.localizedDescription);
            }
        }];
	}];
}

- (void)handleErrorResponse:(QBResponse *)response {

}

- (BOOL)isAuthorized {
	return self.authService.isAuthorized;
}

- (QBUUser *)currentUser {
	return [QBSession currentSession].currentUser;
}

- (void)joinAllGroupDialogsIfNeeded {
    
    if (!self.chatService.isAutoJoinEnabled) {
        // if auto join is not enabled QMServices will not join group chat dialogs automatically.
        return;
    }
    
    NSArray *dialogObjects = [self.chatService.dialogsMemoryStorage unsortedDialogs];
    for (QBChatDialog* dialog in dialogObjects) {
        if (dialog.type != QBChatDialogTypePrivate) {
            // Joining to group chat dialogs.
            [self.chatService joinToGroupDialog:dialog completion:^(NSError *error) {
                //
                if (error != nil) {
                    NSLog(@"Failed to join room with error: %@", error.localizedDescription);
                }
            }];
        }
    }
}

#pragma mark - Caches

- (QMChatCache*) chatCache
{
    if (isCachesCreated) {
        return [QMChatCache instance];
    }
    
    return nil;
}

- (QMUsersCache*) usersCache
{
    if (isCachesCreated)
    {
        return [QMUsersCache instance];
    }
    
    return nil;
}

- (void) cleanCaches
{
    isCachesCreated = NO;
    [QMChatCache cleanDBWithStoreName:@"sample-cache"];
    [QMUsersCache cleanDBWithStoreName:@"qb-users-cache"];
}

- (void) createCachesWithPassword: (NSString*) password
{
    if (!isCachesCreated) {
        isCachesCreated = YES;
        [QMChatCache setupDBWithStoreNamed:@"sample-cache" withPassword: password];
        [QMChatCache instance].messagesLimitPerDialog = kQMMessagesLimitPerDialog;
        [QMUsersCache setupDBWithStoreNamed:@"qb-users-cache" withPassword: password];
    }
}

#pragma mark - QMChatServiceDelegate

- (void)chatServiceChatDidConnect:(QMChatService *)chatService {
    [self joinAllGroupDialogsIfNeeded];
}

- (void)chatServiceChatDidReconnect:(QMChatService *)chatService {
    [self joinAllGroupDialogsIfNeeded];
}

#pragma mark QMChatServiceCache delegate

- (void)chatService:(QMChatService *)chatService didAddChatDialogToMemoryStorage:(QBChatDialog *)chatDialog {
	[[self chatCache] insertOrUpdateDialog:chatDialog completion:nil];
}

- (void)chatService:(QMChatService *)chatService didAddChatDialogsToMemoryStorage:(NSArray *)chatDialogs {
	[[self chatCache] insertOrUpdateDialogs:chatDialogs completion:nil];
}

- (void)chatService:(QMChatService *)chatService didUpdateChatDialogInMemoryStorage:(QBChatDialog *)chatDialog {
	[[self chatCache] insertOrUpdateDialog:chatDialog completion:nil];
}

- (void)chatService:(QMChatService *)chatService didUpdateChatDialogsInMemoryStorage:(NSArray *)dialogs {
    [[self chatCache] insertOrUpdateDialogs:dialogs completion:nil];
}

- (void)chatService:(QMChatService *)chatService didAddMessageToMemoryStorage:(QBChatMessage *)message forDialogID:(NSString *)dialogID {
    [self.chatService markMessageAsDelivered:message completion:nil];
	[[self chatCache] insertOrUpdateMessage:message withDialogId:dialogID completion:nil];
}

- (void)chatService:(QMChatService *)chatService didAddMessagesToMemoryStorage:(NSArray *)messages forDialogID:(NSString *)dialogID {
    [self.chatService markMessagesAsDelivered:messages completion:nil];
	[[self chatCache] insertOrUpdateMessages:messages withDialogId:dialogID completion:nil];
}

- (void)chatService:(QMChatService *)chatService didUpdateMessage:(QBChatMessage *)message forDialogID:(NSString *)dialogID {
    [[self chatCache] insertOrUpdateMessage:message withDialogId:dialogID completion:nil];
}

- (void)chatService:(QMChatService *)chatService didDeleteChatDialogWithIDFromMemoryStorage:(NSString *)chatDialogID {
    [[self chatCache] deleteDialogWithID:chatDialogID completion:nil];
    [[self chatCache] deleteMessageWithDialogID:chatDialogID completion:nil];
}

- (void)chatService:(QMChatService *)chatService didDeleteMessageFromMemoryStorage:(QBChatMessage *)message forDialogID:(NSString *)dialogID {
    [[self chatCache] deleteMessage:message completion:nil];
}

- (void)chatService:(QMChatService *)chatService didDeleteMessagesFromMemoryStorage:(NSArray *)messages forDialogID:(NSString *)dialogID {
    [[self chatCache] deleteMessages:messages completion:nil];
}

- (void)chatService:(QMChatService *)chatService  didReceiveNotificationMessage:(QBChatMessage *)message createDialog:(QBChatDialog *)dialog {
	NSAssert([message.dialogID isEqualToString:dialog.ID], @"must be equal");
	
	[[self chatCache] insertOrUpdateMessage:message withDialogId:dialog.ID completion:nil];
	[[self chatCache] insertOrUpdateDialog:dialog completion:nil];
}

#pragma mark QMChatServiceCacheDataSource

- (void)cachedDialogs:(QMCacheCollection)block {
	[[self chatCache] dialogsSortedBy:CDDialogAttributes.lastMessageDate ascending:YES completion:^(NSArray *dialogs) {
		block(dialogs);
	}];
}

- (void)cachedDialogWithID:(NSString *)dialogID completion:(void (^)(QBChatDialog *dialog))completion {
    [[self chatCache] dialogByID:dialogID completion:^(QBChatDialog *cachedDialog) {
        completion(cachedDialog);
    }];
}

- (void)cachedMessagesWithDialogID:(NSString *)dialogID block:(QMCacheCollection)block {
	[[self chatCache] messagesWithDialogId:dialogID sortedBy:CDMessageAttributes.messageID ascending:YES completion:^(NSArray *array) {
		block(array);
	}];
}

#pragma mark - QMUsersServiceCacheDataSource

- (void)cachedUsers:(QMCacheCollection)block {
    [[[self usersCache] usersSortedBy:@"id" ascending:YES] continueWithExecutor:[BFExecutor mainThreadExecutor]
                                                                          withBlock:^id(BFTask *task) {
                                                                              if (block) block(task.result);
                                                                              return nil;
                                                                          }];
}

#pragma mark - QMUsersServiceDelegate

- (void)usersService:(QMUsersService *)usersService didAddUsers:(NSArray *)users
{
    [[self usersCache] insertOrUpdateUsers:users];
}


@end
