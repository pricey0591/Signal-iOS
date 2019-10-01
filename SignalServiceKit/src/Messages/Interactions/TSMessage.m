//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

#import "TSMessage.h"
#import "AppContext.h"
#import "MIMETypeUtil.h"
#import "OWSContact.h"
#import "OWSDisappearingMessagesConfiguration.h"
#import "TSAttachment.h"
#import "TSAttachmentStream.h"
#import "TSQuotedMessage.h"
#import "TSThread.h"
#import <SignalCoreKit/NSDate+OWS.h>
#import <SignalCoreKit/NSString+OWS.h>
#import <SignalServiceKit/OWSDisappearingMessagesJob.h>
#import <SignalServiceKit/SignalServiceKit-Swift.h>

NS_ASSUME_NONNULL_BEGIN

static const NSUInteger OWSMessageSchemaVersion = 4;

#pragma mark -

@interface TSMessage ()

@property (nonatomic, nullable) NSString *body;
@property (nonatomic) uint32_t expiresInSeconds;
@property (nonatomic) uint64_t expireStartedAt;

/**
 * The version of the model class's schema last used to serialize this model. Use this to manage data migrations during
 * object de/serialization.
 *
 * e.g.
 *
 *    - (id)initWithCoder:(NSCoder *)coder
 *    {
 *      self = [super initWithCoder:coder];
 *      if (!self) { return self; }
 *      if (_schemaVersion < 2) {
 *        _newName = [coder decodeObjectForKey:@"oldName"]
 *      }
 *      ...
 *      _schemaVersion = 2;
 *    }
 */
@property (nonatomic, readonly) NSUInteger schemaVersion;

@property (nonatomic, nullable) TSQuotedMessage *quotedMessage;
@property (nonatomic, nullable) OWSContact *contactShare;
@property (nonatomic, nullable) OWSLinkPreview *linkPreview;
@property (nonatomic, nullable) MessageSticker *messageSticker;

@property (nonatomic) BOOL isViewOnceMessage;
@property (nonatomic) BOOL isViewOnceComplete;

// This property is only intended to be used by GRDB queries.
@property (nonatomic, readonly) BOOL storedShouldStartExpireTimer;

@end

#pragma mark -

@implementation TSMessage

- (instancetype)initMessageWithTimestamp:(uint64_t)timestamp
                                inThread:(TSThread *)thread
                             messageBody:(nullable NSString *)body
                           attachmentIds:(NSArray<NSString *> *)attachmentIds
                        expiresInSeconds:(uint32_t)expiresInSeconds
                         expireStartedAt:(uint64_t)expireStartedAt
                           quotedMessage:(nullable TSQuotedMessage *)quotedMessage
                            contactShare:(nullable OWSContact *)contactShare
                             linkPreview:(nullable OWSLinkPreview *)linkPreview
                          messageSticker:(nullable MessageSticker *)messageSticker
                       isViewOnceMessage:(BOOL)isViewOnceMessage
{
    self = [super initInteractionWithTimestamp:timestamp inThread:thread];

    if (!self) {
        return self;
    }

    _schemaVersion = OWSMessageSchemaVersion;

    _body = body;
    _attachmentIds = attachmentIds ? [attachmentIds mutableCopy] : [NSMutableArray new];
    _expiresInSeconds = expiresInSeconds;
    _expireStartedAt = expireStartedAt;
    [self updateExpiresAt];
    _quotedMessage = quotedMessage;
    _contactShare = contactShare;
    _linkPreview = linkPreview;
    _messageSticker = messageSticker;
    _isViewOnceMessage = isViewOnceMessage;
    _isViewOnceComplete = NO;

    return self;
}

// --- CODE GENERATION MARKER

// This snippet is generated by /Scripts/sds_codegen/sds_generate.py. Do not manually edit it, instead run `sds_codegen.sh`.

// clang-format off

- (instancetype)initWithUniqueId:(NSString *)uniqueId
             receivedAtTimestamp:(uint64_t)receivedAtTimestamp
                          sortId:(uint64_t)sortId
                       timestamp:(uint64_t)timestamp
                  uniqueThreadId:(NSString *)uniqueThreadId
                   attachmentIds:(NSArray<NSString *> *)attachmentIds
                            body:(nullable NSString *)body
                    contactShare:(nullable OWSContact *)contactShare
                 expireStartedAt:(uint64_t)expireStartedAt
                       expiresAt:(uint64_t)expiresAt
                expiresInSeconds:(unsigned int)expiresInSeconds
              isViewOnceComplete:(BOOL)isViewOnceComplete
               isViewOnceMessage:(BOOL)isViewOnceMessage
                     linkPreview:(nullable OWSLinkPreview *)linkPreview
                  messageSticker:(nullable MessageSticker *)messageSticker
                   quotedMessage:(nullable TSQuotedMessage *)quotedMessage
                   schemaVersion:(NSUInteger)schemaVersion
    storedShouldStartExpireTimer:(BOOL)storedShouldStartExpireTimer
{
    self = [super initWithUniqueId:uniqueId
               receivedAtTimestamp:receivedAtTimestamp
                            sortId:sortId
                         timestamp:timestamp
                    uniqueThreadId:uniqueThreadId];

    if (!self) {
        return self;
    }

    _attachmentIds = attachmentIds;
    _body = body;
    _contactShare = contactShare;
    _expireStartedAt = expireStartedAt;
    _expiresAt = expiresAt;
    _expiresInSeconds = expiresInSeconds;
    _isViewOnceComplete = isViewOnceComplete;
    _isViewOnceMessage = isViewOnceMessage;
    _linkPreview = linkPreview;
    _messageSticker = messageSticker;
    _quotedMessage = quotedMessage;
    _schemaVersion = schemaVersion;
    _storedShouldStartExpireTimer = storedShouldStartExpireTimer;

    [self sdsFinalizeMessage];

    return self;
}

// clang-format on

// --- CODE GENERATION MARKER

- (void)sdsFinalizeMessage
{
    [self updateExpiresAt];
}

- (nullable instancetype)initWithCoder:(NSCoder *)coder
{
    self = [super initWithCoder:coder];
    if (!self) {
        return self;
    }

    if (_schemaVersion < 2) {
        // renamed _attachments to _attachmentIds
        if (!_attachmentIds) {
            _attachmentIds = [coder decodeObjectForKey:@"attachments"];
        }
    }

    if (_schemaVersion < 3) {
        _expiresInSeconds = 0;
        _expireStartedAt = 0;
        _expiresAt = 0;
    }

    if (_schemaVersion < 4) {
        // Wipe out the body field on these legacy attachment messages.
        //
        // Explantion: Historically, a message sent from iOS could be an attachment XOR a text message,
        // but now we support sending an attachment+caption as a single message.
        //
        // Other clients have supported sending attachment+caption in a single message for a long time.
        // So the way we used to handle receiving them was to make it look like they'd sent two messages:
        // first the attachment+caption (we'd ignore this caption when rendering), followed by a separate
        // message with just the caption (which we'd render as a simple independent text message), for
        // which we'd offset the timestamp by a little bit to get the desired ordering.
        //
        // Now that we can properly render an attachment+caption message together, these legacy "dummy" text
        // messages are not only unnecessary, but worse, would be rendered redundantly. For safety, rather
        // than building the logic to try to find and delete the redundant "dummy" text messages which users
        // have been seeing and interacting with, we delete the body field from the attachment message,
        // which iOS users have never seen directly.
        if (_attachmentIds.count > 0) {
            _body = nil;
        }
    }

    if (!_attachmentIds) {
        _attachmentIds = [NSMutableArray new];
    }

    _schemaVersion = OWSMessageSchemaVersion;

    // Upgrades legacy messages.
    //
    // TODO: We can eventually remove this migration since
    //       per-message expiration was never released to
    //       production.
    NSNumber *_Nullable perMessageExpirationDurationSeconds =
        [coder decodeObjectForKey:@"perMessageExpirationDurationSeconds"];
    if (perMessageExpirationDurationSeconds.unsignedIntegerValue > 0) {
        _isViewOnceMessage = YES;
    }
    NSNumber *_Nullable perMessageExpirationHasExpired = [coder decodeObjectForKey:@"perMessageExpirationHasExpired"];
    if (perMessageExpirationHasExpired.boolValue > 0) {
        _isViewOnceComplete = YES;
    }

    return self;
}

- (void)setExpiresInSeconds:(uint32_t)expiresInSeconds
{
    uint32_t maxExpirationDuration = [OWSDisappearingMessagesConfiguration maxDurationSeconds];
    if (expiresInSeconds > maxExpirationDuration) {
        OWSFailDebug(@"using `maxExpirationDuration` instead of: %u", maxExpirationDuration);
    }

    _expiresInSeconds = MIN(expiresInSeconds, maxExpirationDuration);
    [self updateExpiresAt];
}

- (void)setExpireStartedAt:(uint64_t)expireStartedAt
{
    if (_expireStartedAt != 0 && _expireStartedAt < expireStartedAt) {
        OWSLogDebug(@"ignoring later startedAt time");
        return;
    }

    uint64_t now = [NSDate ows_millisecondTimeStamp];
    if (expireStartedAt > now) {
        OWSLogWarn(@"using `now` instead of future time");
    }

    _expireStartedAt = MIN(now, expireStartedAt);
    [self updateExpiresAt];
}

// This method will be called after every insert and update, so it needs
// to be cheap.
- (BOOL)shouldStartExpireTimer
{
    if (self.hasPerConversationExpirationStarted) {
        // Expiration already started.
        return YES;
    }

    return self.hasPerConversationExpiration;
}

- (void)updateExpiresAt
{
    if (self.hasPerConversationExpirationStarted) {
        _expiresAt = _expireStartedAt + _expiresInSeconds * 1000;
    } else {
        _expiresAt = 0;
    }
}

#pragma mark - Attachments

- (BOOL)hasAttachments
{
    return self.attachmentIds ? (self.attachmentIds.count > 0) : NO;
}

- (NSArray<NSString *> *)allAttachmentIds
{
    NSMutableArray<NSString *> *result = [NSMutableArray new];
    if (self.attachmentIds.count > 0) {
        [result addObjectsFromArray:self.attachmentIds];
    }

    if (self.quotedMessage) {
        [result addObjectsFromArray:self.quotedMessage.thumbnailAttachmentStreamIds];

        if (self.quotedMessage.thumbnailAttachmentPointerId != nil) {
            [result addObject:self.quotedMessage.thumbnailAttachmentPointerId];
        }
    }

    if (self.contactShare.avatarAttachmentId) {
        [result addObject:self.contactShare.avatarAttachmentId];
    }

    if (self.linkPreview.imageAttachmentId) {
        [result addObject:self.linkPreview.imageAttachmentId];
    }

    if (self.messageSticker.attachmentId) {
        [result addObject:self.messageSticker.attachmentId];
    }

    // Use a set to de-duplicate the result.
    return [NSSet setWithArray:result].allObjects;
}

- (NSArray<TSAttachment *> *)bodyAttachmentsWithTransaction:(SDSAnyReadTransaction *)transaction
{
    return [TSMessage attachmentsWithIds:self.attachmentIds transaction:transaction];
}

- (NSArray<TSAttachment *> *)allAttachmentsWithTransaction:(SDSAnyReadTransaction *)transaction
{
    return [TSMessage attachmentsWithIds:self.allAttachmentIds transaction:transaction];
}

+ (NSArray<TSAttachment *> *)attachmentsWithIds:(NSArray<NSString *> *)attachmentIds
                                    transaction:(SDSAnyReadTransaction *)transaction
{
    NSMutableArray<TSAttachment *> *attachments = [NSMutableArray new];
    for (NSString *attachmentId in attachmentIds) {
        TSAttachment *_Nullable attachment = [TSAttachment anyFetchWithUniqueId:attachmentId transaction:transaction];
        if (attachment) {
            [attachments addObject:attachment];
        }
    }
    return [attachments copy];
}

- (NSArray<TSAttachment *> *)bodyAttachmentsWithTransaction:(SDSAnyReadTransaction *)transaction
                                                contentType:(NSString *)contentType
{
    NSArray<TSAttachment *> *attachments = [self bodyAttachmentsWithTransaction:transaction];
    return [attachments filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(TSAttachment *evaluatedObject,
                                                        NSDictionary<NSString *, id> *_Nullable bindings) {
        return [evaluatedObject.contentType isEqualToString:contentType];
    }]];
}

- (NSArray<TSAttachment *> *)bodyAttachmentsWithTransaction:(SDSAnyReadTransaction *)transaction
                                          exceptContentType:(NSString *)contentType
{
    NSArray<TSAttachment *> *attachments = [self bodyAttachmentsWithTransaction:transaction];
    return [attachments filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(TSAttachment *evaluatedObject,
                                                        NSDictionary<NSString *, id> *_Nullable bindings) {
        return ![evaluatedObject.contentType isEqualToString:contentType];
    }]];
}

- (void)removeAttachment:(TSAttachment *)attachment transaction:(SDSAnyWriteTransaction *)transaction
{
    OWSAssertDebug([self.attachmentIds containsObject:attachment.uniqueId]);
    [attachment anyRemoveWithTransaction:transaction];

    [self anyUpdateMessageWithTransaction:transaction
                                    block:^(TSMessage *message) {
                                        NSMutableArray<NSString *> *attachmentIds = [message.attachmentIds mutableCopy];
                                        [attachmentIds removeObject:attachment.uniqueId];
                                        message.attachmentIds = attachmentIds;
                                    }];
}

- (NSString *)debugDescription
{
    if ([self hasAttachments] && self.body.length > 0) {
        NSString *attachmentId = self.attachmentIds[0];
        return [NSString
            stringWithFormat:@"Media Message with attachmentId: %@ and caption: '%@'", attachmentId, self.body];
    } else if ([self hasAttachments]) {
        NSString *attachmentId = self.attachmentIds[0];
        return [NSString stringWithFormat:@"Media Message with attachmentId: %@", attachmentId];
    } else {
        return [NSString stringWithFormat:@"%@ with body: %@", [self class], self.body];
    }
}

- (nullable TSAttachment *)oversizeTextAttachmentWithTransaction:(SDSAnyReadTransaction *)transaction
{
    return [self bodyAttachmentsWithTransaction:transaction contentType:OWSMimeTypeOversizeTextMessage].firstObject;
}

- (NSArray<TSAttachment *> *)mediaAttachmentsWithTransaction:(SDSAnyReadTransaction *)transaction
{
    return [self bodyAttachmentsWithTransaction:transaction exceptContentType:OWSMimeTypeOversizeTextMessage];
}

- (nullable NSString *)oversizeTextWithTransaction:(SDSAnyReadTransaction *)transaction
{
    TSAttachment *_Nullable attachment = [self oversizeTextAttachmentWithTransaction:transaction];
    if (!attachment) {
        return nil;
    }

    if (![attachment isKindOfClass:TSAttachmentStream.class]) {
        return nil;
    }

    TSAttachmentStream *attachmentStream = (TSAttachmentStream *)attachment;

    NSData *_Nullable data = [NSData dataWithContentsOfFile:attachmentStream.originalFilePath];
    if (!data) {
        OWSFailDebug(@"Can't load oversize text data.");
        return nil;
    }
    NSString *_Nullable text = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    if (!text) {
        OWSFailDebug(@"Can't parse oversize text data.");
        return nil;
    }
    return text.filterStringForDisplay;
}

- (nullable NSString *)bodyTextWithTransaction:(SDSAnyReadTransaction *)transaction
{
    NSString *_Nullable oversizeText = [self oversizeTextWithTransaction:transaction];
    if (oversizeText) {
        return oversizeText;
    }

    if (self.body.length > 0) {
        return self.body.filterStringForDisplay;
    }

    return nil;
}

// TODO: This method contains view-specific logic and probably belongs in NotificationsManager, not in SSK.
- (NSString *)previewTextWithTransaction:(SDSAnyReadTransaction *)transaction
{
    NSString *_Nullable bodyDescription = nil;

    if (self.body.length > 0) {
        bodyDescription = self.body;
    }

    if (bodyDescription == nil) {
        TSAttachment *_Nullable oversizeTextAttachment = [self oversizeTextAttachmentWithTransaction:transaction];
        if ([oversizeTextAttachment isKindOfClass:[TSAttachmentStream class]]) {
            TSAttachmentStream *oversizeTextAttachmentStream = (TSAttachmentStream *)oversizeTextAttachment;
            NSData *_Nullable data = [NSData dataWithContentsOfFile:oversizeTextAttachmentStream.originalFilePath];
            if (data) {
                NSString *_Nullable text = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
                if (text) {
                    bodyDescription = text.filterStringForDisplay;
                }
            }
        }
    }

    NSString *_Nullable attachmentDescription = nil;

    TSAttachment *_Nullable mediaAttachment = [self mediaAttachmentsWithTransaction:transaction].firstObject;
    if (mediaAttachment != nil) {
        attachmentDescription = mediaAttachment.description;
    }

    if (self.isViewOnceMessage) {
        NSString *label = NSLocalizedString(
            @"PER_MESSAGE_EXPIRATION_NOTIFICATION", @"Notification for incoming disappearing photo.");
        if (mediaAttachment != nil) {
            attachmentDescription = [TSAttachment emojiForMimeType:mediaAttachment.contentType];
        }
        if (attachmentDescription.length > 0) {
            return [[attachmentDescription stringByAppendingString:@" "] stringByAppendingString:label];
        } else {
            return label;
        }
    }

    if (attachmentDescription.length > 0 && bodyDescription.length > 0) {
        // Attachment with caption.
        return [[bodyDescription stringByAppendingString:@" "] stringByAppendingString:attachmentDescription];
    } else if (bodyDescription.length > 0) {
        return bodyDescription;
    } else if (attachmentDescription.length > 0) {
        return attachmentDescription;
    } else if (self.contactShare) {
        return [[self.contactShare.name.displayName stringByAppendingString:@" "] stringByAppendingString:@"👤"];
    } else if (self.messageSticker) {
        return NSLocalizedString(
            @"STICKER_MESSAGE_PREVIEW", @"Preview text shown in notifications and home view for sticker messages.");
    } else {
        // This can happen when initially saving outgoing messages with camera first capture
        // over the homeview.
        return @"";
    }
}

- (void)anyWillInsertWithTransaction:(SDSAnyWriteTransaction *)transaction
{
    [super anyWillInsertWithTransaction:transaction];

    // StickerManager does reference counting of "known" sticker packs.
    if (self.messageSticker != nil) {
        BOOL willInsert = (self.uniqueId.length < 1
            || nil == [TSMessage anyFetchWithUniqueId:self.uniqueId transaction:transaction]);

        if (willInsert) {
            [StickerManager addKnownStickerInfo:self.messageSticker.info transaction:transaction];
        }
    }

    [self updateStoredShouldStartExpireTimer];
}

- (void)anyDidInsertWithTransaction:(SDSAnyWriteTransaction *)transaction
{
    [super anyDidInsertWithTransaction:transaction];

    [self ensurePerConversationExpirationWithTransaction:transaction];
}

- (void)anyWillUpdateWithTransaction:(SDSAnyWriteTransaction *)transaction
{
    [super anyWillUpdateWithTransaction:transaction];

    [self updateStoredShouldStartExpireTimer];
}

- (void)anyDidUpdateWithTransaction:(SDSAnyWriteTransaction *)transaction
{
    [super anyDidUpdateWithTransaction:transaction];

    [self ensurePerConversationExpirationWithTransaction:transaction];
}

- (void)ensurePerConversationExpirationWithTransaction:(SDSAnyWriteTransaction *)transaction
{
    if (self.hasPerConversationExpirationStarted) {
        // Expiration already started.
        return;
    }
    if (![self shouldStartExpireTimer]) {
        return;
    }
    uint64_t nowMs = [NSDate ows_millisecondTimeStamp];
    [[OWSDisappearingMessagesJob sharedJob] startAnyExpirationForMessage:self
                                                     expirationStartedAt:nowMs
                                                             transaction:transaction];
}

- (void)updateStoredShouldStartExpireTimer
{
    _storedShouldStartExpireTimer = [self shouldStartExpireTimer];
}

- (void)anyWillRemoveWithTransaction:(SDSAnyWriteTransaction *)transaction
{
    [super anyWillRemoveWithTransaction:transaction];

    // StickerManager does reference counting of "known" sticker packs.
    if (self.messageSticker != nil) {
        BOOL willDelete = (self.uniqueId.length > 0
            && nil != [TSMessage anyFetchWithUniqueId:self.uniqueId transaction:transaction]);

        // StickerManager does reference counting of "known" sticker packs.
        if (willDelete) {
            [StickerManager removeKnownStickerInfo:self.messageSticker.info transaction:transaction];
        }
    }
}

- (void)anyDidRemoveWithTransaction:(SDSAnyWriteTransaction *)transaction
{
    [super anyDidRemoveWithTransaction:transaction];

    [self removeAllAttachmentsWithTransaction:transaction];
}

- (void)removeAllAttachmentsWithTransaction:(SDSAnyWriteTransaction *)transaction
{
    OWSAssertDebug(transaction);

    for (NSString *attachmentId in self.allAttachmentIds) {
        // We need to fetch each attachment, since [TSAttachment removeWithTransaction:] does important work.
        TSAttachment *_Nullable attachment = [TSAttachment anyFetchWithUniqueId:attachmentId transaction:transaction];
        if (!attachment) {
            if (self.shouldBeSaved) {
                OWSFailDebugUnlessRunningTests(@"couldn't load interaction's attachment for deletion.");
            } else {
                OWSLogWarn(@"couldn't load interaction's attachment for deletion.");
            }
            continue;
        }
        [attachment anyRemoveWithTransaction:transaction];
    };
}

- (BOOL)hasPerConversationExpiration
{
    return self.expiresInSeconds > 0;
}

- (BOOL)hasPerConversationExpirationStarted
{
    return self.expireStartedAt > 0;
}

- (uint64_t)timestampForLegacySorting
{
    if ([self shouldUseReceiptDateForSorting] && self.receivedAtTimestamp > 0) {
        return self.receivedAtTimestamp;
    } else {
        OWSAssertDebug(self.timestamp > 0);
        return self.timestamp;
    }
}

- (BOOL)shouldUseReceiptDateForSorting
{
    return YES;
}

- (nullable NSString *)body
{
    return _body.filterStringForDisplay;
}

- (void)setQuotedMessageThumbnailAttachmentStream:(TSAttachmentStream *)attachmentStream
{
    OWSAssertDebug([attachmentStream isKindOfClass:[TSAttachmentStream class]]);
    OWSAssertDebug(self.quotedMessage);
    OWSAssertDebug(self.quotedMessage.quotedAttachments.count == 1);

    [self.quotedMessage setThumbnailAttachmentStream:attachmentStream];
}

#pragma mark - Update With... Methods

- (void)updateWithExpireStartedAt:(uint64_t)expireStartedAt transaction:(SDSAnyWriteTransaction *)transaction
{
    OWSAssertDebug(expireStartedAt > 0);

    [self anyUpdateMessageWithTransaction:transaction
                                    block:^(TSMessage *message) {
                                        [message setExpireStartedAt:expireStartedAt];
                                    }];
}

- (void)updateWithLinkPreview:(OWSLinkPreview *)linkPreview transaction:(SDSAnyWriteTransaction *)transaction
{
    OWSAssertDebug(linkPreview);
    OWSAssertDebug(transaction);

    [self anyUpdateMessageWithTransaction:transaction
                                    block:^(TSMessage *message) {
                                        [message setLinkPreview:linkPreview];
                                    }];
}

- (void)updateWithMessageSticker:(MessageSticker *)messageSticker transaction:(SDSAnyWriteTransaction *)transaction
{
    OWSAssertDebug(messageSticker);
    OWSAssertDebug(transaction);

    [self anyUpdateMessageWithTransaction:transaction
                                    block:^(TSMessage *message) {
                                        message.messageSticker = messageSticker;
                                    }];
}

#ifdef DEBUG

// This method is for testing purposes only.
- (void)updateWithMessageBody:(nullable NSString *)messageBody transaction:(SDSAnyWriteTransaction *)transaction
{
    OWSAssertDebug(transaction);

    [self anyUpdateMessageWithTransaction:transaction
                                    block:^(TSMessage *message) {
                                        message.body = messageBody;
                                    }];
}

#endif

#pragma mark - Renderable Content

- (BOOL)hasRenderableContent
{
    return (
        self.body.length > 0 || self.attachmentIds.count > 0 || self.contactShare != nil || self.messageSticker != nil);
}

#pragma mark - View Once

- (void)updateWithViewOnceCompleteAndRemoveRenderableContentWithTransaction:(SDSAnyWriteTransaction *)transaction
{
    OWSAssertDebug(transaction);
    OWSAssertDebug(self.isViewOnceMessage);
    OWSAssertDebug(!self.isViewOnceComplete);

    // We call removeAllAttachmentsWithTransaction() before
    // anyUpdateWithTransaction, because anyUpdateWithTransaction's
    // block can be called twice, once on this instance and once
    // on the copy from the database.  We only want to remove
    // attachments once.
    [self anyReloadWithTransaction:transaction ignoreMissing:YES];
    [self removeAllAttachmentsWithTransaction:transaction];

    [self anyUpdateMessageWithTransaction:transaction
                                    block:^(TSMessage *message) {
                                        message.isViewOnceComplete = YES;

                                        // Remove renderable content.
                                        message.body = nil;
                                        message.contactShare = nil;
                                        message.quotedMessage = nil;
                                        message.linkPreview = nil;
                                        message.messageSticker = nil;
                                        message.attachmentIds = [NSMutableArray new];
                                        OWSAssertDebug(!message.hasRenderableContent);
                                    }];
}

@end

NS_ASSUME_NONNULL_END
