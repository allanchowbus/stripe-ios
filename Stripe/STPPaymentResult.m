//
//  STPPaymentResult.m
//  Stripe
//
//  Created by Jack Flintermann on 1/15/16.
//  Copyright © 2016 Stripe, Inc. All rights reserved.
//

#import "STPPaymentResult.h"
#import "STPAddress.h"

@interface STPPaymentResult()
@end

@implementation STPPaymentResult

- (nonnull instancetype)initWithSource:(id<STPSource>)source {
    self = [super init];
    if (self) {
        _source = source;
    }
    return self;
}
@end
