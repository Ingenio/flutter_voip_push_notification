#import "FlutterVoipPushNotificationPlugin.h"

NSString *const FlutterVoipRemoteNotificationsRegistered = @"voipRemoteNotificationsRegistered";
NSString *const FlutterVoipLocalNotificationReceived = @"voipLocalNotificationReceived";
NSString *const FlutterVoipRemoteNotificationReceived = @"voipRemoteNotificationReceived";
NSString *const VOIP_MESSAGE_CHANNEL_NAME = @"flutter.ingenio.com/on_message";
NSString *const VOIP_RESUME_CHANNEL_NAME = @"flutter.ingenio.com/on_resume";

BOOL RunningInAppExtension(void)
{
    return [[[[NSBundle mainBundle] bundlePath] pathExtension] isEqualToString:@"appex"];
}

@implementation FlutterVoipPushNotificationPlugin {
    FlutterMethodChannel* _channel;
    BOOL _resumingFromBackground;
    PKPushRegistry * _voipRegistry;
}

+ (void)registerWithRegistrar:(NSObject<FlutterPluginRegistrar>*)registrar {
    FlutterVoipPushNotificationPlugin* instance = [[FlutterVoipPushNotificationPlugin alloc] initWithRegistrar:registrar messenger:[registrar messenger]];
    instance.messageStreamHandler = [MessageStreamHandler new];
    instance.resumeStreamHandler = [ResumeStreamHandler new];
    
    [[FlutterEventChannel eventChannelWithName:VOIP_MESSAGE_CHANNEL_NAME
                               binaryMessenger:[registrar messenger]] setStreamHandler:instance.messageStreamHandler];
    
    [[FlutterEventChannel eventChannelWithName:VOIP_RESUME_CHANNEL_NAME
                               binaryMessenger:[registrar messenger]] setStreamHandler:instance.resumeStreamHandler];
    [registrar addApplicationDelegate:instance];
    NSDateFormatter *dateFormatter = [[NSDateFormatter alloc] init];
    [dateFormatter setDateFormat:@"HH:mm:ss.SSS"];
    NSDate *currentDate = [NSDate date];
    NSString *currentTime = [dateFormatter stringFromDate:currentDate];
    NSLog(@"[FlutterVoipPushNotificationPlugin] registerWithRegistrar time = %@", currentTime);
}

- (instancetype)initWithRegistrar:(NSObject<FlutterPluginRegistrar>*)registrar
                        messenger:(NSObject<FlutterBinaryMessenger>*)messenger{
    
    self = [super init];
    
    if (self) {
        _channel = [FlutterMethodChannel
                    methodChannelWithName:@"com.peerwaya/flutter_voip_push_notification"
                    binaryMessenger:[registrar messenger]];
        [registrar addMethodCallDelegate:self channel:_channel];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(handleRemoteNotificationsRegistered:)
                                                     name:FlutterVoipRemoteNotificationsRegistered
                                                   object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(handleLocalNotificationReceived:)
                                                     name:FlutterVoipLocalNotificationReceived
                                                   object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(handleRemoteNotificationReceived:)
                                                     name:FlutterVoipRemoteNotificationReceived
                                                   object:nil];
    }
    return self;
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)handleMethodCall:(FlutterMethodCall*)call result:(FlutterResult)result {
    NSString *method = call.method;
    if ([@"requestNotificationPermissions" isEqualToString:method]) {
        if (RunningInAppExtension()) {
            result(nil);
            return;
        }
        [self registerUserNotification:call.arguments result:result];
    }if ([@"checkPermissions" isEqualToString:method]) {
        if (RunningInAppExtension()) {
            result(@{@"alert": @NO, @"badge": @NO, @"sound": @NO});
            return;
        }
        result([self checkPermissions]);
    }if ([@"presentLocalNotification" isEqualToString:method]) {
        [self presentLocalNotification:call.arguments];
        result(nil);
    }if ([@"getToken" isEqualToString:method]) {
        result([self getToken]);
    }else {
        result(FlutterMethodNotImplemented);
    }
}

- (void)registerUserNotification:(NSDictionary *)permissions result:(FlutterResult)result
{
    UIUserNotificationType notificationTypes = 0;
    if ([permissions[@"sound"] boolValue]) {
        notificationTypes |= UIUserNotificationTypeSound;
    }
    if ([permissions[@"alert"] boolValue]) {
        notificationTypes |= UIUserNotificationTypeAlert;
    }
    if ([permissions[@"badge"] boolValue]) {
        notificationTypes |= UIUserNotificationTypeBadge;
    }
    UIUserNotificationSettings *settings =
    [UIUserNotificationSettings settingsForTypes:notificationTypes categories:nil];
    [[UIApplication sharedApplication] registerUserNotificationSettings:settings];
    result(nil);
}

- (NSDictionary *)checkPermissions
{
    NSUInteger types = [[UIApplication sharedApplication] currentUserNotificationSettings].types;
    return @{
        @"alert": @((types & UIUserNotificationTypeAlert) > 0),
        @"badge": @((types & UIUserNotificationTypeBadge) > 0),
        @"sound": @((types & UIUserNotificationTypeSound) > 0),
    };
}

- (void)voipRegistration
{
    NSLog(@"[FlutterVoipPushNotificationPlugin] voipRegistration");
    dispatch_queue_t mainQueue = dispatch_get_main_queue();
    // Create a push registry object
    _voipRegistry = [[PKPushRegistry alloc] initWithQueue: mainQueue];
    // Set the registry's delegate to self
    _voipRegistry.delegate = (FlutterVoipPushNotificationPlugin *)[UIApplication sharedApplication].delegate;
    // Set the push type to VoIP
    _voipRegistry.desiredPushTypes = [NSSet setWithObject:PKPushTypeVoIP];
}

- (void)presentLocalNotification:(UILocalNotification *)notification
{
    [[UIApplication sharedApplication] presentLocalNotificationNow:notification];
}

#pragma mark - AppDelegate

- (BOOL)application:(UIApplication *)application
didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    [self voipRegistration];
    return YES;
}

- (void)applicationDidEnterBackground:(UIApplication *)application {
    _resumingFromBackground = YES;
}

- (void)applicationDidBecomeActive:(UIApplication *)application {
    _resumingFromBackground = NO;
}


- (NSString*)getToken
{
    NSMutableString *hexString = [NSMutableString string];
    NSData* token = [_voipRegistry pushTokenForType:PKPushTypeVoIP];
    NSUInteger voipTokenLength = token.length;
    const unsigned char *bytes = token.bytes;
    for (NSUInteger i = 0; i < voipTokenLength; i++) {
        [hexString appendFormat:@"%02x", bytes[i]];
    }
    return hexString;
}

#pragma mark - PKPushRegistryDelegate methods

+ (void)didUpdatePushCredentials:(PKPushCredentials *)credentials forType:(NSString *)type
{
    NSLog(@"[FlutterVoipPushNotificationPlugin] didUpdatePushCredentials credentials.token = %@, type = %@", credentials.token, type);
    
    NSMutableString *hexString = [NSMutableString string];
    NSUInteger voipTokenLength = credentials.token.length;
    const unsigned char *bytes = credentials.token.bytes;
    for (NSUInteger i = 0; i < voipTokenLength; i++) {
        [hexString appendFormat:@"%02x", bytes[i]];
    }
    [[NSNotificationCenter defaultCenter] postNotificationName:FlutterVoipRemoteNotificationsRegistered
                                                        object:self
                                                      userInfo:@{@"deviceToken" : [hexString copy]}];
    
}

+ (void)didReceiveIncomingPushWithPayload:(PKPushPayload *)payload forType:(NSString *)type
{
    NSDateFormatter *dateFormatter = [[NSDateFormatter alloc] init];
    [dateFormatter setDateFormat:@"HH:mm:ss.SSS"];
    NSDate *currentDate = [NSDate date];
    NSString *currentTime = [dateFormatter stringFromDate:currentDate];
    NSLog(@"[FlutterVoipPushNotificationPlugin] didReceiveIncomingPushWithPayload payload.dictionaryPayload = %@, type = %@, time = %@", payload.dictionaryPayload, type, currentTime);
    [[NSNotificationCenter defaultCenter] postNotificationName:FlutterVoipRemoteNotificationReceived
                                                        object:self
                                                      userInfo:payload.dictionaryPayload];
}

- (void)handleRemoteNotificationsRegistered:(NSNotification *)notification
{
    NSDateFormatter *dateFormatter = [[NSDateFormatter alloc] init];
    [dateFormatter setDateFormat:@"HH:mm:ss.SSS"];
    NSDate *currentDate = [NSDate date];
    NSString *currentTime = [dateFormatter stringFromDate:currentDate];
    NSLog(@"[FlutterVoipPushNotificationPlugin] handleRemoteNotificationsRegistered notification.userInfo = %@, time = %@", notification.userInfo, currentTime);
    [_channel invokeMethod:@"onToken" arguments:notification.userInfo];
}

- (void)handleLocalNotificationReceived:(NSNotification *)notification
{
#ifdef DEBUG
    NSDateFormatter *dateFormatter = [[NSDateFormatter alloc] init];
    [dateFormatter setDateFormat:@"HH:mm:ss.SSS"];
    NSDate *currentDate = [NSDate date];
    NSString *currentTime = [dateFormatter stringFromDate:currentDate];
    NSLog(@"[FlutterVoipPushNotificationPlugin] handleLocalNotificationReceived notification.userInfo = %@, time = %@", notification.userInfo, currentTime);
#endif
    if (_resumingFromBackground) {
        [self.resumeStreamHandler sendResume: notification.userInfo];
    } else {
        [self.messageStreamHandler sendMessage: notification.userInfo];
    }
}

- (void)handleRemoteNotificationReceived:(NSNotification *)notification
{
#ifdef DEBUG
    NSDateFormatter *dateFormatter = [[NSDateFormatter alloc] init];
    [dateFormatter setDateFormat:@"HH:mm:ss.SSS"];
    NSDate *currentDate = [NSDate date];
    NSString *currentTime = [dateFormatter stringFromDate:currentDate];
    NSLog(@"[FlutterVoipPushNotificationPlugin] handleRemoteNotificationReceived notification.userInfo = %@, time = %@", notification.userInfo, currentTime);
#endif
    if (_resumingFromBackground) {
        [self.resumeStreamHandler sendResume: notification.userInfo];
    } else {
        [self.messageStreamHandler sendMessage: notification.userInfo];
    }
}

@end

@implementation MessageStreamHandler

- (FlutterError*)onListenWithArguments:(id)arguments eventSink:(FlutterEventSink)eventSink {
    self.eventSink = eventSink;
    return nil;
}

- (FlutterError*)onCancelWithArguments:(id)arguments {
    self.eventSink = nil;
    return nil;
}

- (void) sendMessage: (NSString *)message {
    if(self.eventSink) {
        self.eventSink(message);
    }
}

@end

@implementation ResumeStreamHandler

- (FlutterError*)onListenWithArguments:(id)arguments eventSink:(FlutterEventSink)eventSink {
    self.eventSink = eventSink;
    return nil;
}

- (FlutterError*)onCancelWithArguments:(id)arguments {
    self.eventSink = nil;
    return nil;
}

- (void) sendResume: (NSString *)resume {
    if(self.eventSink) {
        self.eventSink(resume);
    }
}

@end
