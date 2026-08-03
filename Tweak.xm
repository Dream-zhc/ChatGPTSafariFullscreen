#import <UIKit/UIKit.h>
#import <WebKit/WebKit.h>
#import <objc/runtime.h>
#import <objc/message.h>

static void *SGURLObservationContext = &SGURLObservationContext;
static const void *SGObservedWebViewKey = &SGObservedWebViewKey;
static const void *SGGestureInstalledKey = &SGGestureInstalledKey;
static const void *SGChromeStateKey = &SGChromeStateKey;

@interface SGStoredViewState : NSObject
@property (nonatomic) BOOL hidden;
@property (nonatomic) CGFloat alpha;
@property (nonatomic) BOOL userInteractionEnabled;
@end
@implementation SGStoredViewState
@end

@interface SGFullscreenManager : NSObject <UIGestureRecognizerDelegate>
@property (nonatomic, strong) NSURL *currentURL;
@property (nonatomic, copy) NSString *currentHost;
@property (nonatomic) BOOL manualBarsVisible;
@property (nonatomic) BOOL fullscreenApplied;
@property (nonatomic) BOOL applyScheduled;
@property (nonatomic) BOOL diagnosticLogged;
@property (nonatomic) NSTimeInterval lastApplyTime;
+ (instancetype)shared;
- (void)start;
- (void)registerWebView:(WKWebView *)webView;
- (void)unregisterWebView:(WKWebView *)webView;
- (void)registerWindow:(UIWindow *)window;
- (void)scheduleEvaluation;
- (void)scheduleChromeApply;
@end

@implementation SGFullscreenManager

+ (instancetype)shared {
    static SGFullscreenManager *manager;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        manager = [SGFullscreenManager new];
    });
    return manager;
}

- (void)start {
    NSNotificationCenter *center = NSNotificationCenter.defaultCenter;
    [center addObserver:self selector:@selector(applicationDidBecomeActive:) name:UIApplicationDidBecomeActiveNotification object:nil];
    [center addObserver:self selector:@selector(applicationWillResignActive:) name:UIApplicationWillResignActiveNotification object:nil];
    dispatch_async(dispatch_get_main_queue(), ^{
        for (UIWindow *window in UIApplication.sharedApplication.windows) {
            [self registerWindow:window];
        }
        [self scheduleEvaluation];
    });
}

- (void)applicationDidBecomeActive:(NSNotification *)notification {
    (void)notification;
    [self scheduleEvaluation];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.8 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [self scheduleEvaluation];
    });
}

- (void)applicationWillResignActive:(NSNotification *)notification {
    (void)notification;
}

- (void)registerWebView:(WKWebView *)webView {
    if (!webView || objc_getAssociatedObject(webView, SGObservedWebViewKey)) {
        return;
    }

    @try {
        [webView addObserver:self
                  forKeyPath:@"URL"
                     options:NSKeyValueObservingOptionInitial | NSKeyValueObservingOptionNew
                     context:SGURLObservationContext];
        objc_setAssociatedObject(webView, SGObservedWebViewKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    } @catch (NSException *exception) {
        NSLog(@"[ChatGPTSafariFullscreen] Failed to observe WKWebView URL: %@", exception);
    }
}

- (void)unregisterWebView:(WKWebView *)webView {
    if (!webView || !objc_getAssociatedObject(webView, SGObservedWebViewKey)) {
        return;
    }

    @try {
        [webView removeObserver:self forKeyPath:@"URL" context:SGURLObservationContext];
    } @catch (__unused NSException *exception) {
    }
    objc_setAssociatedObject(webView, SGObservedWebViewKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

- (void)observeValueForKeyPath:(NSString *)keyPath
                      ofObject:(id)object
                        change:(NSDictionary<NSKeyValueChangeKey,id> *)change
                       context:(void *)context {
    if (context == SGURLObservationContext && [object isKindOfClass:WKWebView.class]) {
        (void)keyPath;
        (void)change;
        WKWebView *webView = (WKWebView *)object;
        dispatch_async(dispatch_get_main_queue(), ^{
            if ([self isWebViewActuallyVisible:webView]) {
                [self updateForURL:webView.URL];
            }
        });
        return;
    }
    [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
}

- (void)registerWindow:(UIWindow *)window {
    if (!window || objc_getAssociatedObject(window, SGGestureInstalledKey)) {
        return;
    }

    UITapGestureRecognizer *gesture = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(toggleGestureRecognized:)];
    gesture.numberOfTouchesRequired = 3;
    gesture.numberOfTapsRequired = 2;
    gesture.cancelsTouchesInView = NO;
    gesture.delaysTouchesBegan = NO;
    gesture.delaysTouchesEnded = NO;
    gesture.delegate = self;
    [window addGestureRecognizer:gesture];
    objc_setAssociatedObject(window, SGGestureInstalledKey, gesture, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)otherGestureRecognizer {
    (void)gestureRecognizer;
    (void)otherGestureRecognizer;
    return YES;
}

- (void)toggleGestureRecognized:(UITapGestureRecognizer *)gesture {
    if (gesture.state != UIGestureRecognizerStateRecognized || ![self isChatGPTHost:self.currentHost]) {
        return;
    }
    self.manualBarsVisible = !self.manualBarsVisible;
    NSLog(@"[ChatGPTSafariFullscreen] Manual toolbar override: %@", self.manualBarsVisible ? @"visible" : @"hidden");
    [self applyDesiredChromeState];
}

- (BOOL)isWebViewActuallyVisible:(WKWebView *)webView {
    UIWindow *window = webView.window;
    if (!window || window.hidden || webView.hidden || webView.alpha < 0.01) {
        return NO;
    }
    CGRect rect = [webView convertRect:webView.bounds toView:window];
    CGRect intersection = CGRectIntersection(rect, window.bounds);
    if (CGRectIsNull(intersection) || CGRectIsEmpty(intersection)) {
        return NO;
    }
    CGFloat visibleArea = intersection.size.width * intersection.size.height;
    CGFloat totalArea = MAX(1.0, rect.size.width * rect.size.height);
    return visibleArea / totalArea > 0.25;
}

- (void)scheduleEvaluation {
    dispatch_async(dispatch_get_main_queue(), ^{
        NSURL *bestURL = nil;
        CGFloat bestArea = 0;
        for (UIWindow *window in UIApplication.sharedApplication.windows) {
            [self registerWindow:window];
            WKWebView *candidate = [self largestVisibleWebViewInView:window];
            if (!candidate || !candidate.URL) {
                continue;
            }
            CGRect rect = [candidate convertRect:candidate.bounds toView:window];
            CGFloat area = rect.size.width * rect.size.height;
            if (area > bestArea) {
                bestArea = area;
                bestURL = candidate.URL;
            }
        }
        if (bestURL) {
            [self updateForURL:bestURL];
        } else {
            [self scheduleChromeApply];
        }
    });
}

- (WKWebView *)largestVisibleWebViewInView:(UIView *)view {
    WKWebView *best = nil;
    CGFloat bestArea = 0;
    NSMutableArray<UIView *> *stack = [NSMutableArray arrayWithObject:view];
    while (stack.count) {
        UIView *current = stack.lastObject;
        [stack removeLastObject];
        if ([current isKindOfClass:WKWebView.class]) {
            WKWebView *webView = (WKWebView *)current;
            [self registerWebView:webView];
            if ([self isWebViewActuallyVisible:webView]) {
                CGRect rect = [webView convertRect:webView.bounds toView:webView.window];
                CGFloat area = rect.size.width * rect.size.height;
                if (area > bestArea) {
                    bestArea = area;
                    best = webView;
                }
            }
        }
        for (UIView *subview in current.subviews) {
            if (!subview.hidden && subview.alpha > 0.01) {
                [stack addObject:subview];
            }
        }
    }
    return best;
}

- (void)updateForURL:(NSURL *)URL {
    if (!URL) {
        return;
    }
    NSString *host = URL.host.lowercaseString ?: @"";
    if (host.length == 0) {
        return;
    }

    BOOL hostChanged = ![host isEqualToString:self.currentHost ?: @""];
    self.currentURL = URL;
    self.currentHost = host;
    if (hostChanged) {
        self.manualBarsVisible = NO;
        NSLog(@"[ChatGPTSafariFullscreen] Active host: %@", host);
    }
    [self applyDesiredChromeState];
}

- (BOOL)isChatGPTHost:(NSString *)host {
    if (host.length == 0) {
        return NO;
    }
    return [host isEqualToString:@"chatgpt.com"] ||
           [host hasSuffix:@".chatgpt.com"] ||
           [host isEqualToString:@"chat.openai.com"] ||
           [host hasSuffix:@".chat.openai.com"];
}

- (BOOL)isAuthenticationHost:(NSString *)host {
    if (host.length == 0) {
        return NO;
    }
    NSArray<NSString *> *authSuffixes = @[
        @"auth.openai.com",
        @"auth0.openai.com",
        @"accounts.google.com",
        @"appleid.apple.com",
        @"login.microsoftonline.com",
        @"live.com",
        @"okta.com",
        @"cloudflare.com",
        @"challenges.cloudflare.com"
    ];
    for (NSString *suffix in authSuffixes) {
        if ([host isEqualToString:suffix] || [host hasSuffix:[@"." stringByAppendingString:suffix]]) {
            return YES;
        }
    }
    return NO;
}

- (void)applyDesiredChromeState {
    BOOL shouldHide = [self isChatGPTHost:self.currentHost] &&
                      ![self isAuthenticationHost:self.currentHost] &&
                      !self.manualBarsVisible;
    [self setChromeHidden:shouldHide];
}

- (void)scheduleChromeApply {
    if (self.applyScheduled) {
        return;
    }
    self.applyScheduled = YES;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.08 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        self.applyScheduled = NO;
        [self applyDesiredChromeState];
    });
}

- (void)setChromeHidden:(BOOL)hidden {
    NSTimeInterval now = NSDate.timeIntervalSinceReferenceDate;
    if (hidden == self.fullscreenApplied && now - self.lastApplyTime < 0.45) {
        return;
    }
    self.fullscreenApplied = hidden;
    self.lastApplyTime = now;

    BOOL invokedNativeAction = [self sendSafariBarActionHidden:hidden];
    BOOL invokedControllerAPI = [self invokeControllerBarAPIsHidden:hidden];
    if (!invokedNativeAction && !invokedControllerAPI) {
        [self setFallbackChromeViewsHidden:hidden];
    } else if (!hidden) {
        [self setFallbackChromeViewsHidden:NO];
    }

    if (!self.diagnosticLogged) {
        self.diagnosticLogged = YES;
        NSLog(@"[ChatGPTSafariFullscreen] Loaded. Native action=%d controller API=%d. Triple-finger double-tap toggles Safari chrome.", invokedNativeAction, invokedControllerAPI);
    }
}

- (BOOL)sendSafariBarActionHidden:(BOOL)hidden {
    NSArray<NSString *> *selectorNames = hidden ? @[
        @"hideBars:", @"_hideBars:", @"hideToolbar:", @"_hideToolbar:",
        @"hideBrowserChrome:", @"_hideBrowserChrome:"
    ] : @[
        @"showBars:", @"_showBars:", @"showToolbar:", @"_showToolbar:",
        @"showBrowserChrome:", @"_showBrowserChrome:"
    ];

    UIApplication *application = UIApplication.sharedApplication;
    for (NSString *name in selectorNames) {
        SEL selector = NSSelectorFromString(name);
        if ([application sendAction:selector to:nil from:nil forEvent:nil]) {
            return YES;
        }
    }
    return NO;
}

- (BOOL)invokeControllerBarAPIsHidden:(BOOL)hidden {
    __block BOOL invoked = NO;
    for (UIWindow *window in UIApplication.sharedApplication.windows) {
        UIViewController *root = window.rootViewController;
        if (!root) {
            continue;
        }
        [self walkController:root block:^(UIViewController *controller) {
            NSString *className = NSStringFromClass(controller.class);
            NSString *lower = className.lowercaseString;
            BOOL looksSafariOwned = [lower containsString:@"safari"] ||
                                    [lower containsString:@"browser"] ||
                                    [lower containsString:@"tab"] ||
                                    [lower containsString:@"navigation"] ||
                                    [lower containsString:@"root"];
            if (!looksSafariOwned) {
                return;
            }

            NSArray<NSString *> *twoArgumentSelectors = @[
                @"setBarsHidden:animated:", @"_setBarsHidden:animated:",
                @"setChromeHidden:animated:", @"_setChromeHidden:animated:",
                @"setBrowserChromeHidden:animated:", @"_setBrowserChromeHidden:animated:",
                @"setToolbarHidden:animated:", @"_setToolbarHidden:animated:",
                @"setNavigationBarHidden:animated:", @"setBottomBarHidden:animated:"
            ];
            for (NSString *name in twoArgumentSelectors) {
                SEL selector = NSSelectorFromString(name);
                if ([controller respondsToSelector:selector]) {
                    ((void (*)(id, SEL, BOOL, BOOL))objc_msgSend)(controller, selector, hidden, NO);
                    invoked = YES;
                }
            }

            NSArray<NSString *> *oneArgumentSelectors = @[
                @"setBarsHidden:", @"_setBarsHidden:",
                @"setChromeHidden:", @"_setChromeHidden:",
                @"setBrowserChromeHidden:", @"_setBrowserChromeHidden:",
                @"setToolbarHidden:", @"_setToolbarHidden:"
            ];
            for (NSString *name in oneArgumentSelectors) {
                SEL selector = NSSelectorFromString(name);
                if ([controller respondsToSelector:selector]) {
                    ((void (*)(id, SEL, BOOL))objc_msgSend)(controller, selector, hidden);
                    invoked = YES;
                }
            }
        }];
    }
    return invoked;
}

- (void)walkController:(UIViewController *)controller block:(void (^)(UIViewController *controller))block {
    if (!controller || !block) {
        return;
    }
    block(controller);
    if (controller.presentedViewController) {
        [self walkController:controller.presentedViewController block:block];
    }
    for (UIViewController *child in controller.childViewControllers) {
        [self walkController:child block:block];
    }
}

- (BOOL)viewIsInsideWebContent:(UIView *)view {
    UIView *cursor = view;
    while (cursor) {
        if ([cursor isKindOfClass:WKWebView.class]) {
            return YES;
        }
        NSString *name = NSStringFromClass(cursor.class);
        if ([name hasPrefix:@"WK"] || [name containsString:@"WebContent"]) {
            return YES;
        }
        cursor = cursor.superview;
    }
    return NO;
}

- (BOOL)isLikelySafariChromeView:(UIView *)view inWindow:(UIWindow *)window {
    if (!view || !window || [self viewIsInsideWebContent:view]) {
        return NO;
    }

    NSString *className = NSStringFromClass(view.class);
    NSString *lower = className.lowercaseString;
    if ([lower containsString:@"keyboard"] || [lower containsString:@"inputset"] ||
        [lower containsString:@"alert"] || [lower containsString:@"popover"] ||
        [lower hasPrefix:@"wk"] || [lower containsString:@"statusbar"]) {
        return NO;
    }

    NSArray<NSString *> *tokens = @[
        @"browsertoolbar", @"safaritoolbar", @"unifiedbar", @"unifiedfield",
        @"navigationbar", @"tabbar", @"bottomtoolbar", @"toptoolbar",
        @"bottombar", @"toolbar"
    ];
    BOOL classMatches = NO;
    for (NSString *token in tokens) {
        if ([lower containsString:token]) {
            classMatches = YES;
            break;
        }
    }
    if (!classMatches) {
        return NO;
    }

    CGRect rect = [view convertRect:view.bounds toView:window];
    if (CGRectIsEmpty(rect) || CGRectIsNull(rect)) {
        return NO;
    }
    CGFloat windowHeight = CGRectGetHeight(window.bounds);
    CGFloat windowWidth = CGRectGetWidth(window.bounds);
    BOOL nearTop = CGRectGetMinY(rect) < 190.0;
    BOOL nearBottom = CGRectGetMaxY(rect) > windowHeight - 190.0;
    BOOL plausibleSize = CGRectGetWidth(rect) > windowWidth * 0.45 && CGRectGetHeight(rect) < 190.0;
    return plausibleSize && (nearTop || nearBottom);
}

- (void)setFallbackChromeViewsHidden:(BOOL)hidden {
    for (UIWindow *window in UIApplication.sharedApplication.windows) {
        if (window.hidden || window.windowLevel > UIWindowLevelNormal + 1.0) {
            continue;
        }
        NSMutableArray<UIView *> *stack = [NSMutableArray arrayWithObject:window];
        while (stack.count) {
            UIView *view = stack.lastObject;
            [stack removeLastObject];

            SGStoredViewState *stored = objc_getAssociatedObject(view, SGChromeStateKey);
            if (hidden && [self isLikelySafariChromeView:view inWindow:window]) {
                if (!stored) {
                    stored = [SGStoredViewState new];
                    stored.hidden = view.hidden;
                    stored.alpha = view.alpha;
                    stored.userInteractionEnabled = view.userInteractionEnabled;
                    objc_setAssociatedObject(view, SGChromeStateKey, stored, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                }
                view.userInteractionEnabled = NO;
                view.alpha = 0.0;
                view.hidden = YES;
            } else if (!hidden && stored) {
                view.hidden = stored.hidden;
                view.alpha = stored.alpha;
                view.userInteractionEnabled = stored.userInteractionEnabled;
                objc_setAssociatedObject(view, SGChromeStateKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            }

            for (UIView *subview in view.subviews) {
                [stack addObject:subview];
            }
        }
    }
}

@end

%hook WKWebView

- (void)didMoveToWindow {
    %orig;
    if (self.window) {
        [[SGFullscreenManager shared] registerWebView:self];
        [[SGFullscreenManager shared] scheduleEvaluation];
    }
}

- (void)dealloc {
    [[SGFullscreenManager shared] unregisterWebView:self];
    %orig;
}

%end

%hook UIWindow

- (void)makeKeyAndVisible {
    %orig;
    [[SGFullscreenManager shared] registerWindow:self];
    [[SGFullscreenManager shared] scheduleEvaluation];
}


%end

%hook UIViewController

- (void)viewDidAppear:(BOOL)animated {
    %orig(animated);
    [[SGFullscreenManager shared] scheduleChromeApply];
}

- (void)viewSafeAreaInsetsDidChange {
    %orig;
    [[SGFullscreenManager shared] scheduleChromeApply];
}

%end

%ctor {
    @autoreleasepool {
        NSString *bundleID = NSBundle.mainBundle.bundleIdentifier;
        if ([bundleID isEqualToString:@"com.apple.mobilesafari"]) {
            [[SGFullscreenManager shared] start];
            NSLog(@"[ChatGPTSafariFullscreen] Initializing in MobileSafari");
        }
    }
}
