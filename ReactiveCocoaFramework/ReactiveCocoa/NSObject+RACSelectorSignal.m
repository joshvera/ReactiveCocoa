//
//  NSObject+RACSelectorSignal.m
//  ReactiveCocoa
//
//  Created by Josh Abernathy on 3/18/13.
//  Copyright (c) 2013 GitHub, Inc. All rights reserved.
//

#import "NSObject+RACSelectorSignal.h"
#import "RACSubject.h"
#import "NSObject+RACPropertySubscribing.h"
#import "RACDisposable.h"
#import <objc/runtime.h>

static const void *RACObjectSelectorSignals = &RACObjectSelectorSignals;

@implementation NSObject (RACSelectorSignal)

static RACSignal *NSObjectRACSignalForSelector(id self, SEL _cmd, SEL selector) {
	NSParameterAssert([NSStringFromSelector(selector) componentsSeparatedByString:@":"].count == 2);

	@synchronized(self) {
		NSMutableDictionary *selectorSignals = objc_getAssociatedObject(self, RACObjectSelectorSignals);
		if (selectorSignals == nil) {
			selectorSignals = [NSMutableDictionary dictionary];
			objc_setAssociatedObject(self, RACObjectSelectorSignals, selectorSignals, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
		}

		NSString *key = NSStringFromSelector(selector);
		RACTuple *subjectAndProxy = selectorSignals[key];
		RACSubject *subject = subjectAndProxy.first;
		if (subject) return subject;

		subject = [RACSubject subject];
		subjectAndProxy.first = subject;

		subjectAndProxy.second = [[RACLiftProxy alloc] initWithTarget:self selector:selector];
		selectorSignals[key] = subjectAndProxy;


		[self rac_addDeallocDisposable:[RACDisposable disposableWithBlock:^{
			[subject sendCompleted];
			selectorSignals[key] = nil;
		}]];

		return subject;
	}
}

- (RACSignal *)rac_signalForSelector:(SEL)selector {
	return NSObjectRACSignalForSelector(self, _cmd, selector);
}

+ (RACSignal *)rac_signalForSelector:(SEL)selector {
	return NSObjectRACSignalForSelector(self, _cmd, selector);
}

@end
