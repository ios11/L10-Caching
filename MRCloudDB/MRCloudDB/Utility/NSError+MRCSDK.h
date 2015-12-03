//
//  NSError+MRCSDK.h
//  MRCloudSDK
//
//  Created by Pavel Osipov on 01.10.12.
//  Copyright (c) 2012 Mail.Ru. All rights reserved.
//

FOUNDATION_EXTERN NSString * const MRCloudSDKErrorDomain;

typedef NS_ENUM(NSInteger, MRCErrorCode) {
    MRCAuthenticationError = 1000,
    MRCAuthorizationError,
    MRCBlobError,
    MRCInternalError,
    MRCMetadServerError,
    MRCNetworkError,
    MRCServerError,
    MRCSystemError,
    MRCUnknownError,
    MRCUserTypeError // The minimal value for error code with MRCloudSDKErrorDomain
};

typedef NS_ENUM(NSInteger, MRCHTTPStatusCode) {
    MRCHTTPStatusCodeUnknown   = -1,
    MRCHTTPStatusCodeForbidden = 403,
    MRCHTTPStatusCodeNotFound  = 404
};

typedef NS_ENUM(uint8_t, MRCMetadStatusCode) {
    MRCMetadStatusCodeSuccess                     = 0,   // успех
    MRCMetadStatusCodeNodeNotFoundError           = 1,   // нет такого файла или директории
    MRCMetadStatusCodeNodeIsDirectoryError        = 2,   // запрашиваемый объект является директорией, а не файлом
    MRCMetadStatusCodeIOError                     = 3,   // ошибка ввода-вывода при обращении к диску
    MRCMetadStatusCodeNodeAlreadyExistError       = 4,   // ошибка создания файла - такой файл уже существует
    MRCMetadStatusCodeNodeIsFileError             = 5,   // часть указанного пути файла существует, но не является директорией
    MRCMetadStatusCodeDirectoryIsNotEmptyError    = 6,   // попытка удалить непустую директорию
    MRCMetadStatusCodeNotEnoughSpaceError         = 7,   // недостаточно свободного места
    MRCMetadStatusCodeNameTooLongError            = 8,   // слишком длинное имя файла
    MRCMetadStatusCodeNameCaseConflictError       = 9,   // объект с таким же именем в другом регистре уже существует
    MRCMetadStatusCodeBadNameError                = 10,  // недопустимый символ в имени файла или каталога
    MRCMetadStatusCodeAccessDeniedError           = 11,  // отказано в доступе
    MRCMetadStatusCodeContentNotModified          = 12,  // содержимое не изменилось
    MRCMetadStatusCodeNoMemoryError               = 200, // не удалось выполнить операцию на сервере из-за нехватки памяти (временная ошибка)
    MRCMetadStatusCodeServiceTemporaryUnavailable = 249, // сервис недоступен. Этой ошибке сопустсвует расширенный формат ответа (см 4.4)
    MRCMetadStatusCodeClientOutdatedError         = 250, // клиент нуждается в обновлении
    MRCMetadStatusCodeCommandNotImplementedError  = 251, // команда не реализована (на текущий момент нигде не используется)
    MRCMetadStatusCodeCommandOutdatedError        = 252, // клиент послал команду, которая больше не поддерживается, рекомендуется обновление клиента
    MRCMetadStatusCodeBadBlobError                = 253, // неверно указана информация о блобе (блоб не существует или имеет отличный от указанного размер)
    MRCMetadStatusCodeMetadataVersionOutdated     = 254, // попытка применить изменения не к самой свежей версии хранилища
    MRCMetadStatusCodeUnknownError                = 255  // неизвестная ошибка
};

@interface NSError (MRCSDK)

@property (nonatomic, readonly) MRCErrorCode mrc_code;
@property (nonatomic, readonly) MRCHTTPStatusCode mrc_HTTPStatusCode;
@property (nonatomic, readonly) MRCMetadStatusCode mrc_metadStatusCode;

- (BOOL)mrc_isCloudError;
- (BOOL)mrc_isAuthorizationError;
- (BOOL)mrc_isClientOutdatedError;

+ (NSError *)mrc_authenticationError;
+ (NSError *)mrc_authorizationErrorWithReason:(NSError *)reason;
+ (NSError *)mrc_blobErrorWithReason:(NSError *)reason format:(NSString *)format, ...;
+ (NSError *)mrc_internalErrorWithFormat:(NSString *)format, ...;
+ (NSError *)mrc_metadErrorWithStatusCode:(MRCMetadStatusCode)code;
+ (NSError *)mrc_networkErrorWithReason:(NSError *)reason;
+ (NSError *)mrc_serverErrorWithFormat:(NSString *)format, ...;
+ (NSError *)mrc_serverErrorWithReason:(NSError *)reason format:(NSString *)format, ...;
+ (NSError *)mrc_serverErrorWithHTTPStatusCode:(NSInteger)HTTPCode URL:(NSURL *)URL;
+ (NSError *)mrc_systemErrorWithReason:(NSError *)reason;
+ (NSError *)mrc_systemErrorWithFormat:(NSString *)format, ...;

@end

NS_INLINE void MRCAssignError(NSError **targetError, NSError *sourceError) {
    if (targetError) {
        *targetError = sourceError;
    }
}
