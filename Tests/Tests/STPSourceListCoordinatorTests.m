//
//  STPSourceListCoordinatorTests.m
//  Stripe
//
//  Created by Ben Guo on 4/11/16.
//  Copyright © 2016 Stripe, Inc. All rights reserved.
//

#import <XCTest/XCTest.h>
#import <Stripe/Stripe.h>
#import "MockSTPAPIClient.h"
#import "MockSTPSourceProvider.h"
#import "MockSTPCoordinatorDelegate.h"
#import "MockUINavigationController.h"
#import "STPSourceListCoordinator.h"
#import "STPSourceListViewController.h"
#import "STPPaymentCardEntryViewController.h"

@interface STPSourceListCoordinator()<STPPaymentCardEntryViewControllerDelegate, STPSourceListViewControllerDelegate>
@property(nonatomic, weak) STPSourceListViewController *sourceListViewController;
@end

@interface STPSourceListCoordinatorTests : XCTestCase

@property (nonatomic, strong) STPSourceListCoordinator *sut;
@property (nonatomic, strong) MockUINavigationController *navigationController;
@property (nonatomic, strong) MockSTPAPIClient *apiClient;
@property (nonatomic, strong) MockSTPSourceProvider *sourceProvider;
@property (nonatomic, strong) MockSTPCoordinatorDelegate *delegate;
@property (nonatomic, strong) STPCardParams *card;

@end

@implementation STPSourceListCoordinatorTests

- (void)setUp {
    [super setUp];
    self.navigationController = [MockUINavigationController new];
    self.apiClient = [[MockSTPAPIClient alloc] initWithPublishableKey:@"foo"];
    self.sourceProvider = [MockSTPSourceProvider new];
    self.delegate = [MockSTPCoordinatorDelegate new];
    self.sut = [[STPSourceListCoordinator alloc] initWithNavigationController:self.navigationController
                                                                    apiClient:self.apiClient
                                                               sourceProvider:self.sourceProvider
                                                                     delegate:self.delegate];
    STPCardParams *card = [[STPCardParams alloc] init];
    card.number = @"4242 4242 4242 4242";
    card.expMonth = 6;
    card.expYear = 2018;
    card.currency = @"usd";
    self.card = card;
}

- (void)tearDown {
    [super tearDown];
    self.navigationController = nil;
    self.apiClient = nil;
    self.sourceProvider = nil;
    self.delegate = nil;
    self.sut = nil;
    self.card = nil;
}

- (void)testBeginShowsSourceListVC {
    [self.sut begin];
    UIViewController *topVC = self.sut.navigationController.topViewController;
    XCTAssertTrue([topVC isKindOfClass:[STPSourceListViewController class]]);
}

- (void)testAddButtonPushesPaymentCardVC {
    XCTestExpectation *exp = [self expectationWithDescription:@"push"];
    __weak id weakSelf = self;
    self.navigationController.onPushViewController = ^(UIViewController *vc, BOOL animated) {
        _XCTPrimitiveAssertTrue(weakSelf, [vc isKindOfClass:[STPPaymentCardEntryViewController class]], @"");
        _XCTPrimitiveAssertTrue(weakSelf, animated, @"");
        [exp fulfill];
    };

    [self.sut sourceListViewControllerDidTapAddButton:self.sut.sourceListViewController];
    [self waitForExpectationsWithTimeout:2 handler:nil];
}

- (void)testAddThenCancelPopsPaymentCardVC {
    XCTestExpectation *pushExp = [self expectationWithDescription:@"pop"];
    XCTestExpectation *popExp = [self expectationWithDescription:@"pop"];
    __weak typeof(self) weakSelf = self;
    self.navigationController.onPushViewController = ^(UIViewController *vc, __unused BOOL animated) {
        _XCTPrimitiveAssertTrue(weakSelf, [vc isKindOfClass:[STPPaymentCardEntryViewController class]], @"");
        [weakSelf.sut paymentCardEntryViewControllerDidCancel:nil];
        [pushExp fulfill];
    };
    self.navigationController.onPopViewController = ^(BOOL animated) {
        UIViewController *topVC = weakSelf.sut.navigationController.topViewController;
        _XCTPrimitiveAssertTrue(weakSelf, [topVC isKindOfClass:[STPPaymentCardEntryViewController class]], @"");
        _XCTPrimitiveAssertTrue(weakSelf, animated, @"");
        [popExp fulfill];
    };

    [self.sut sourceListViewControllerDidTapAddButton:self.sut.sourceListViewController];
    [self waitForExpectationsWithTimeout:2 handler:nil];
}

- (void)testEnterCard_success {
    XCTestExpectation *popExp = [self expectationWithDescription:@"pop"];
    XCTestExpectation *completionExp = [self expectationWithDescription:@"completion"];
    XCTAssertTrue(self.sourceProvider.sources.count == 0);
    self.apiClient.createTokenWithCardBlock = ^(__unused STPCardParams *card, STPTokenCompletionBlock completion) {
        STPToken *token = [STPToken new];
        completion(token, nil);
    };
    __weak typeof(self) weakSelf = self;
    self.navigationController.onPushViewController = ^(__unused UIViewController *vc, __unused BOOL animated) {
        [weakSelf.sut paymentCardEntryViewController:nil didEnterCardParams:weakSelf.card completion:^(NSError * _Nullable error) {
            _XCTPrimitiveAssertNil(weakSelf, error, @"");
            [completionExp fulfill];
        }];
    };
    self.navigationController.onPopViewController = ^(__unused BOOL animated) {
        _XCTPrimitiveAssertTrue(weakSelf, weakSelf.sourceProvider.sources.count == 1, @"");
        [popExp fulfill];
    };

    [self.sut sourceListViewControllerDidTapAddButton:self.sut.sourceListViewController];
    [self waitForExpectationsWithTimeout:2 handler:nil];
}

- (void)testEnterCard_apiClientError {
    XCTestExpectation *exp = [self expectationWithDescription:@"completion"];
    NSError *expectedError = [[NSError alloc] initWithDomain:@"foo" code:123 userInfo:@{}];
    self.apiClient.createTokenWithCardBlock = ^(__unused STPCardParams *card, STPTokenCompletionBlock completion) {
        completion(nil, expectedError);
    };
    __weak typeof(self) weakSelf = self;
    self.navigationController.onPushViewController = ^(__unused UIViewController *vc, __unused BOOL animated) {
        [weakSelf.sut paymentCardEntryViewController:nil didEnterCardParams:weakSelf.card completion:^(NSError * _Nullable error) {
            _XCTPrimitiveAssertEqualObjects(weakSelf, error, @"", expectedError, @"");
            [exp fulfill];
        }];
    };
    self.navigationController.onPopViewController = ^(__unused BOOL animated) {
        _XCTPrimitiveFail(weakSelf, "should not be called");
    };

    [self.sut sourceListViewControllerDidTapAddButton:self.sut.sourceListViewController];
    [self waitForExpectationsWithTimeout:1 handler:nil];
}

- (void)testEnterCard_sourceProviderError {
    XCTestExpectation *exp = [self expectationWithDescription:@"completion"];
    NSError *expectedError = [[NSError alloc] initWithDomain:@"foo" code:123 userInfo:@{}];
    self.sourceProvider.addSourceError = expectedError;
    self.apiClient.createTokenWithCardBlock = ^(__unused STPCardParams *card, STPTokenCompletionBlock completion) {
        STPToken *token = [STPToken new];
        completion(token, nil);
    };
    __weak typeof(self) weakSelf = self;
    self.navigationController.onPushViewController = ^(__unused UIViewController *vc, __unused BOOL animated) {
        [weakSelf.sut paymentCardEntryViewController:nil didEnterCardParams:weakSelf.card completion:^(NSError * _Nullable error) {
            _XCTPrimitiveAssertEqualObjects(weakSelf, error, @"", expectedError, @"");
            [exp fulfill];
        }];
    };
    self.navigationController.onPopViewController = ^(__unused BOOL animated) {
        _XCTPrimitiveFail(weakSelf, "should not be called");
    };

    [self.sut sourceListViewControllerDidTapAddButton:self.sut.sourceListViewController];
    [self waitForExpectationsWithTimeout:1 handler:nil];
}

- (void)testSelectCard_success {
    STPToken *token1 = [STPToken new];
    STPToken *token2 = [STPToken new];
    self.sourceProvider.sources = @[token1, token2];
    self.sourceProvider.selectedSource = token1;

    XCTestExpectation *popExp = [self expectationWithDescription:@"pop"];
    __weak typeof(self) weakSelf = self;
    self.navigationController.onPopViewController = ^(BOOL animated) {
        UIViewController *topVC = weakSelf.sut.navigationController.topViewController;
        _XCTPrimitiveAssertTrue(weakSelf, [topVC isKindOfClass:[STPSourceListViewController class]], @"");
        _XCTPrimitiveAssertTrue(weakSelf, animated, @"");
        _XCTPrimitiveAssertEqualObjects(weakSelf, weakSelf.sourceProvider.selectedSource, @"", token2, @"");
        [popExp fulfill];
    };

    [self.sut begin];
    [self.sut sourceListViewController:self.sut.sourceListViewController didSelectSource:token2];
    [self waitForExpectationsWithTimeout:1 handler:nil];
}

- (void)testSelectCard_error {
    STPToken *token1 = [STPToken new];
    STPToken *token2 = [STPToken new];
    self.sourceProvider.sources = @[token1, token2];
    self.sourceProvider.selectedSource = token1;
    self.sourceProvider.selectSourceError = [[NSError alloc] initWithDomain:@"foo" code:123 userInfo:@{}];
    __weak typeof(self) weakSelf = self;
    self.navigationController.onPopViewController = ^(__unused BOOL animated) {
        _XCTPrimitiveFail(weakSelf, "should not be called");
    };

    [self.sut begin];
    [self.sut sourceListViewController:self.sut.sourceListViewController didSelectSource:token2];
    XCTAssertEqualObjects(self.sourceProvider.selectedSource, token1);
}

@end