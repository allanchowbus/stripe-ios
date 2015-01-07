//
//  STPCheckoutViewController.m
//  StripeExample
//
//  Created by Jack Flintermann on 9/15/14.
//

#import "STPCheckoutViewController.h"
#import "STPCheckoutOptions.h"
#import "STPToken.h"
#import "Stripe.h"
#import "STPColorUtils.h"
#import "STPStrictURLProtocol.h"
#import "STPCheckoutWebViewAdapter.h"
#import "STPCheckoutDelegate.h"

#define FAUXPAS_IGNORED_IN_METHOD(...)

#if TARGET_OS_IPHONE
#pragma mark - iOS

#import "STPIOSCheckoutWebViewAdapter.h"
#import "STPCheckoutInternalUIWebViewController.h"

@interface STPCheckoutViewController ()
@property (nonatomic, weak) STPCheckoutInternalUIWebViewController *webViewController;
@property (nonatomic) UIStatusBarStyle previousStyle;
@end

@implementation STPCheckoutViewController

- (instancetype)initWithOptions:(STPCheckoutOptions *)options {
    STPCheckoutInternalUIWebViewController *webViewController = [[STPCheckoutInternalUIWebViewController alloc] initWithCheckoutViewController:self];
    webViewController.options = options;
    self = [super initWithRootViewController:webViewController];
    if (self) {
        _webViewController = webViewController;
        _previousStyle = [[UIApplication sharedApplication] statusBarStyle];
        if ([[UIDevice currentDevice] userInterfaceIdiom] == UIUserInterfaceIdiomPad) {
            self.modalTransitionStyle = UIModalTransitionStyleCrossDissolve;
        }
    }
    return self;
}

- (void)viewWillAppear:(BOOL)animated {
    NSCAssert(self.checkoutDelegate, @"You must provide a delegate to STPCheckoutViewController before showing it.");
    [super viewWillAppear:animated];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [[UIApplication sharedApplication] setStatusBarStyle:self.previousStyle animated:YES];
}

- (UIViewController *)childViewControllerForStatusBarStyle {
    return self.webViewController;
}

- (void)setCheckoutDelegate:(id<STPCheckoutViewControllerDelegate>)delegate {
    self.webViewController.delegate = delegate;
}

- (id<STPCheckoutViewControllerDelegate>)checkoutDelegate {
    return self.webViewController.delegate;
}

- (STPCheckoutOptions *)options {
    return self.webViewController.options;
}

@end

#else // OSX
#pragma mark - OSX

@interface STPCheckoutViewController () <STPCheckoutDelegate>
@property (nonatomic) STPCheckoutOSXWebViewAdapter *adapter;
@end

@implementation STPCheckoutViewController

- (instancetype)initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil {
    return [self initWithOptions:nil];
}

- (instancetype)initWithCoder:(NSCoder *)coder {
    return [self initWithOptions:nil];
}

- (instancetype)initWithOptions:(STPCheckoutOptions *)options {
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        _options = options;
        static dispatch_once_t onceToken;
        dispatch_once(&onceToken, ^{ [NSURLProtocol registerClass:[STPStrictURLProtocol class]]; });
    }
    return self;
}

- (void)loadView {
    NSView *view = [[NSView alloc] initWithFrame:CGRectZero];
    self.view = view;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    if (!self.adapter) {
        self.adapter = [STPCheckoutOSXWebViewAdapter new];
        self.adapter.delegate = self;
        NSURL *url = [NSURL URLWithString:checkoutURLString];
        [self.adapter loadRequest:[NSURLRequest requestWithURL:url]];
    }
    NSView *webView = self.adapter.webView;
    [self.view addSubview:webView];
    webView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"H:|-0-[webView]-0-|"
                                                                      options:NSLayoutFormatDirectionLeadingToTrailing
                                                                      metrics:nil
                                                                        views:NSDictionaryOfVariableBindings(webView)]];
    [self.view addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"V:|-0-[webView]-0-|"
                                                                      options:NSLayoutFormatDirectionLeadingToTrailing
                                                                      metrics:nil
                                                                        views:NSDictionaryOfVariableBindings(webView)]];
}

- (void)viewDidAppear {
    [super viewDidAppear];
}

#pragma mark STPCheckoutAdapterDelegate

- (void)checkoutAdapterDidStartLoad:(id<STPCheckoutWebViewAdapter>)adapter {
    NSString *optionsJavaScript = [NSString stringWithFormat:@"window.%@ = %@;", checkoutOptionsGlobal, [self.options stringifiedJSONRepresentation]];
    [adapter evaluateJavaScript:optionsJavaScript];
}

- (void)checkoutAdapter:(id<STPCheckoutWebViewAdapter>)adapter didTriggerEvent:(NSString *)event withPayload:(NSDictionary *)payload {
    if ([event isEqualToString:@"CheckoutDidOpen"]) {
        // no-op for now
    } else if ([event isEqualToString:@"CheckoutDidTokenize"]) {
        STPToken *token = nil;
        if (payload != nil && payload[@"token"] != nil) {
            token = [[STPToken alloc] initWithAttributeDictionary:payload[@"token"]];
        }
        [self.checkoutDelegate checkoutController:self
                                   didCreateToken:token
                                       completion:^(STPBackendChargeResult status, NSError *error) {
                                           if (status == STPBackendChargeResultSuccess) {
                                               [adapter evaluateJavaScript:payload[@"success"]];
                                           } else {
                                               NSString *failure = payload[@"failure"];
                                               NSString *script = [NSString stringWithFormat:failure, error.localizedDescription];
                                               [adapter evaluateJavaScript:script];
                                           }
                                       }];
    } else if ([event isEqualToString:@"CheckoutDidFinish"]) {
        [self.checkoutDelegate checkoutControllerDidFinish:self];
    } else if ([event isEqualToString:@"CheckoutDidCancel"]) {
        [self.checkoutDelegate checkoutControllerDidCancel:self];
    } else if ([event isEqualToString:@"CheckoutDidError"]) {
        NSError *error = [[NSError alloc] initWithDomain:StripeDomain code:STPCheckoutError userInfo:payload];
        [self.checkoutDelegate checkoutController:self didFailWithError:error];
    }
}

- (void)checkoutAdapterDidFinishLoad:(__unused id<STPCheckoutWebViewAdapter>)adapter {
}

- (void)checkoutAdapter:(__unused id<STPCheckoutWebViewAdapter>)adapter didError:(__unused NSError *)error {
    [self.checkoutDelegate checkoutController:self didFailWithError:error];
}

@end

#endif
