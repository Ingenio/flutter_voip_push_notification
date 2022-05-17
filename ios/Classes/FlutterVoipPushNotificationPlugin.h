#import <Flutter/Flutter.h>
#import <PushKit/PushKit.h>

@class MessageStreamHandler;
@class ResumeStreamHandler;

@interface FlutterVoipPushNotificationPlugin : NSObject<FlutterPlugin>
@property (nonatomic, strong) MessageStreamHandler *messageStreamHandler;
@property (nonatomic, strong) ResumeStreamHandler *resumeStreamHandler;
+ (void)didUpdatePushCredentials:(PKPushCredentials *)credentials forType:(NSString *)type;
+ (void)didReceiveIncomingPushWithPayload:(PKPushPayload *)payload forType:(NSString *)type;
@end

@interface MessageStreamHandler : NSObject <FlutterStreamHandler>
@property (nonatomic, strong) FlutterEventSink eventSink;

- (void)sendMessage: (NSString *)message;

@end

@interface ResumeStreamHandler : NSObject <FlutterStreamHandler>
@property (nonatomic, strong) FlutterEventSink eventSink;

- (void) sendResume: (NSString *)resume;

@end

@interface MissingArgumentException : NSException
@end