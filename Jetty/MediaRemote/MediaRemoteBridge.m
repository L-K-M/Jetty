#import "MediaRemoteBridge.h"
#import <dlfcn.h>
#import <objc/message.h>

// Poll cadence for the macOS 15.4+ MRNowPlayingController path.
static const NSInteger kControllerPollIntervalMs = 60;
static const NSInteger kControllerMaxPolls = 20;   // ~1.2s budget

typedef void (*MRGetInfoFn)(dispatch_queue_t, void (^)(CFDictionaryRef));

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"

/// Maps the 15.4+ controller `response` object into a legacy-keyed info dictionary.
static NSDictionary *JettyBuildInfoFromResponse(id response) {
    if (!response) return nil;
    @try {
    NSMutableDictionary *info = [NSMutableDictionary dictionary];

    NSNumber *rateNum = [response valueForKey:@"playbackRate"];
    if (rateNum) {
        info[@"kMRMediaRemoteNowPlayingInfoPlaybackRate"] = rateNum;
        if ([rateNum floatValue] == 0.0f) {
            NSNumber *stateNum = [response valueForKey:@"playbackState"];
            if (stateNum) {
                info[@"kMRMediaRemoteNowPlayingInfoPlaybackRate"] =
                    ([stateNum unsignedIntValue] == 1) ? @(1.0) : @(0.0);
            }
        }
    }

    id queue = [response valueForKey:@"playbackQueue"];
    if (!queue) return (info.count > 0) ? info : nil;

    NSArray *items = [queue valueForKey:@"contentItems"];
    if (![items isKindOfClass:[NSArray class]] || items.count == 0) {
        return (info.count > 0) ? info : nil;
    }

    NSNumber *locNum = [queue valueForKey:@"location"];
    NSInteger location = [locNum integerValue];
    id item = (location >= 0 && location < (NSInteger)items.count) ? items[(NSUInteger)location] : items[0];

    id meta = [item valueForKey:@"metadata"];
    if (!meta) return (info.count > 0) ? info : nil;

    void (^add)(NSString *, NSString *) = ^(NSString *metaKey, NSString *infoKey) {
        id value = [meta valueForKey:metaKey];
        if (value) info[infoKey] = value;
    };
    add(@"title",           @"kMRMediaRemoteNowPlayingInfoTitle");
    add(@"trackArtistName", @"kMRMediaRemoteNowPlayingInfoArtist");
    add(@"albumName",       @"kMRMediaRemoteNowPlayingInfoAlbum");
    add(@"duration",        @"kMRMediaRemoteNowPlayingInfoDuration");
    add(@"elapsedTime",     @"kMRMediaRemoteNowPlayingInfoElapsedTime");

    return (info.count > 0) ? info : nil;
    } @catch (NSException *ex) {
        // A renamed/removed private selector must fail closed (return nil → plain glyph),
        // never take down the menu-bar agent (C4).
        return nil;
    }
}

@implementation JettyNowPlaying

+ (void)fetch:(void (^)(NSDictionary<NSString *, id> * _Nullable))completion {
    if (@available(macOS 15.4, *)) {
        [self fetchViaController:completion];
    } else {
        [self fetchViaLegacy:completion];
    }
}

/// Legacy C API (macOS < 15.4): one async callback with a CFDictionary.
+ (void)fetchViaLegacy:(void (^)(NSDictionary * _Nullable))completion {
    void *handle = dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_NOW);
    // Early exits must still honor the header's main-queue contract (FAB-B17).
    if (!handle) { dispatch_async(dispatch_get_main_queue(), ^{ completion(nil); }); return; }
    MRGetInfoFn getInfo = (MRGetInfoFn)dlsym(handle, "MRMediaRemoteGetNowPlayingInfo");
    if (!getInfo) { dispatch_async(dispatch_get_main_queue(), ^{ completion(nil); }); return; }
    getInfo(dispatch_get_main_queue(), ^(CFDictionaryRef information) {
        NSDictionary *info = (__bridge NSDictionary *)information;
        completion((info.count > 0) ? info : nil);
    });
}

/// macOS 15.4+ path: build a private MRNowPlayingController, begin loading, and poll
/// its `response` until it carries data (or we give up).
+ (void)fetchViaController:(void (^)(NSDictionary * _Nullable))completion {
    Class destClass     = NSClassFromString(@"MRDestination");
    Class configClass   = NSClassFromString(@"MRNowPlayingControllerConfiguration");
    Class controllerCls = NSClassFromString(@"MRNowPlayingController");
    // Early exit must still honor the header's main-queue contract (FAB-B17).
    if (!destClass || !configClass || !controllerCls) { dispatch_async(dispatch_get_main_queue(), ^{ completion(nil); }); return; }

    @try {
    // Route `init…` through a typed objc_msgSend (not -performSelector:), so ARC keeps
    // the alloc/init ownership balanced and doesn't over-release the instance.
    id (*msgSendInit)(id, SEL, id) = (id (*)(id, SEL, id))objc_msgSend;

    id dest = [destClass performSelector:NSSelectorFromString(@"userSelectedDestination")];

    id config = msgSendInit([configClass alloc], NSSelectorFromString(@"initWithDestination:"), dest);
    [config setValue:@NO  forKey:@"singleShot"];
    [config setValue:@YES forKey:@"requestPlaybackState"];
    [config setValue:@YES forKey:@"requestPlaybackQueue"];

    __block id controller = msgSendInit([controllerCls alloc], NSSelectorFromString(@"initWithConfiguration:"), config);
    [controller performSelector:NSSelectorFromString(@"beginLoadingUpdates")];

    __block NSInteger pollCount = 0;
    __block BOOL done = NO;

    dispatch_source_t timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue());
    dispatch_source_set_timer(timer, DISPATCH_TIME_NOW,
                              (uint64_t)kControllerPollIntervalMs * NSEC_PER_MSEC,
                              (uint64_t)(kControllerPollIntervalMs / 10) * NSEC_PER_MSEC);
    dispatch_source_set_event_handler(timer, ^{
        if (done) { dispatch_source_cancel(timer); return; }
        @try {
            pollCount++;
            id response = [controller valueForKey:@"response"];
            NSDictionary *info = JettyBuildInfoFromResponse(response);
            BOOL hasData = (info != nil && info.count > 0);
            if (hasData || pollCount >= kControllerMaxPolls) {
                done = YES;
                dispatch_source_cancel(timer);
                [controller performSelector:NSSelectorFromString(@"endLoadingUpdates")];
                controller = nil;
                completion(info);
            }
        } @catch (NSException *ex) {
            // A renamed private selector must fail closed, not crash the agent (C4).
            done = YES;
            dispatch_source_cancel(timer);
            controller = nil;
            completion(nil);
        }
    });
    dispatch_resume(timer);
    } @catch (NSException *ex) {
        // Any renamed/removed private selector in the setup path → fail closed (C4),
        // still on the main queue per the header contract (FAB-B17).
        dispatch_async(dispatch_get_main_queue(), ^{ completion(nil); });
    }
}

@end

#pragma clang diagnostic pop
