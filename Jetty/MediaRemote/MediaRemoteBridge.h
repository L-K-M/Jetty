#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Bridges Apple's private MediaRemote framework to read the system "now playing"
/// track (ND-3). Uses the legacy `MRMediaRemoteGetNowPlayingInfo` C API on macOS
/// < 15.4, and the private `MRNowPlayingController` Objective-C class (via the
/// Objective-C runtime) on 15.4+ / Tahoe, where the legacy callback returns nothing.
///
/// Technique adapted from kirtan-shah/nowplaying-cli (tested on macOS 13–26).
/// Everything is best-effort: if the private API yields nothing, the completion is
/// called with `nil`, so the dock tile simply shows "nothing playing". Result keys
/// are the legacy `kMRMediaRemoteNowPlayingInfo*` strings (Title / Artist / Album /
/// PlaybackRate / Duration / ElapsedTime), regardless of which path produced them.
@interface JettyNowPlaying : NSObject

/// Asynchronously fetches the current now-playing info. `completion` is called on the
/// main queue with the info dictionary, or `nil` if nothing is playing / unavailable.
+ (void)fetch:(void (^)(NSDictionary<NSString *, id> * _Nullable info))completion;

@end

NS_ASSUME_NONNULL_END
