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

	@synchronized(self) {
		NSMutableDictionary *selectorSignals = objc_getAssociatedObject(self, RACObjectSelectorSignals);
		if (selectorSignals == nil) {
			selectorSignals = [NSMutableDictionary dictionary];
			objc_setAssociatedObject(self, RACObjectSelectorSignals, selectorSignals, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
		}

		NSString *key = NSStringFromSelector(selector);
		RACSubject *subject = selectorSignals[key];
		if (subject != nil) return subject;

		subject = [RACReplaySubject replaySubjectWithCapacity:1];

		Class originalClass = object_getClass(self);
		Method originalMethod = class_getInstanceMethod(originalClass, selector);
		SEL newSelector = NSSelectorFromString([NSString stringWithFormat:@"override_%@", NSStringFromSelector(selector)]);

		IMP imp = imp_implementationWithBlock(^(id self, id arg) {
			[self performSelector:newSelector];
			[subject sendNext:arg];
		});

		NSString *originalClassName = NSStringFromClass(originalClass);
		NSArray *components = [originalClassName componentsSeparatedByString:@"_"];
		NSString *KVOName = components[0];
		NSString *originalName = components[1];
		NSString *name = [NSString stringWithFormat:@"%@_%@_RACSelectorSignal_%@", KVOName, NSStringFromSelector(selector), originalName];

		Class original = NSClassFromString(originalName);
		Class newClass = NSClassFromString(name);

		if (newClass == nil)  {
			newClass = objc_allocateClassPair(original, name.UTF8String, 0);

			objc_registerClassPair(newClass);

			BOOL success = class_addMethod(newClass, newSelector, imp, method_getTypeEncoding(originalMethod));
			NSAssert(success, @"%@ is already implemented on %@. %@ will not replace the existing implementation.", NSStringFromSelector(selector), newClass, NSStringFromSelector(_cmd));
			if (!success) return nil;

			Method newMethod = class_getInstanceMethod(newClass, newSelector);
			if (newMethod == nil) return nil;

			method_exchangeImplementations(originalMethod, newMethod);
		}

		Class previousClass = class_setSuperclass(originalClass, newClass);
		if (previousClass == nil) return nil;


		selectorSignals[key] = subject;

		[self rac_addDeallocDisposable:[RACDisposable disposableWithBlock:^{
			[subject sendCompleted];
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
