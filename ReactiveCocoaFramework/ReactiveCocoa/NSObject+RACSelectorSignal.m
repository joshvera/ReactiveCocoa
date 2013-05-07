//
//  NSObject+RACSelectorSignal.m
//  ReactiveCocoa
//
//  Created by Josh Abernathy on 3/18/13.
//  Copyright (c) 2013 GitHub, Inc. All rights reserved.
//

#import "NSObject+RACSelectorSignal.h"
#import "NSInvocation+RACTypeParsing.h"
#import "RACReplaySubject.h"
#import "RACTuple.h"
#import "NSObject+RACPropertySubscribing.h"
#import "RACDisposable.h"
#import <objc/runtime.h>

static const void *RACObjectSelectorSignals = &RACObjectSelectorSignals;

static void RACForwardInvocation(id self, SEL _cmd, NSInvocation *invocation) {
    Ivar var = class_getInstanceVariable(object_getClass(self), "_rac_originalObject");
    id proxy = object_getIvar(self, var);

    invocation.target = proxy;
    [invocation invoke];
}

static BOOL RACRespondsToSelector(id self, SEL _cmd, SEL selector) {
    Ivar var = class_getInstanceVariable(object_getClass(self), "_rac_originalObject");
    id proxy = object_getIvar(self, var);
    return [proxy respondsToSelector:selector];
}

static NSMethodSignature *RACMethodSignatureForSelector(id self, SEL _cmd, SEL selector) {
    Ivar var = class_getInstanceVariable(object_getClass(self), "_rac_originalObject");
    id proxy = object_getIvar(self, var);
    NSMethodSignature* signature = [proxy methodSignatureForSelector:selector];
    return signature;
}


@implementation NSObject (RACSelectorSignal)

static RACSubject *NSObjectRACSignalForSelector(id self, SEL _cmd, SEL selector) {
	NSParameterAssert([NSStringFromSelector(selector) componentsSeparatedByString:@":"].count == 2);

	@synchronized(self) {
		NSMutableDictionary *selectorSignals = objc_getAssociatedObject(self, RACObjectSelectorSignals);
		if (selectorSignals == nil) {
			selectorSignals = [NSMutableDictionary dictionary];
			objc_setAssociatedObject(self, RACObjectSelectorSignals, selectorSignals, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
		}

		NSString *key = NSStringFromSelector(selector);
		RACSubject *subject = selectorSignals[key];
		if (subject != nil) return subject;

		subject = [RACSubject subject];

		Method method = class_getInstanceMethod([self class], selector);

		const char * prefix = "RACSelectorSignal_";
		Class originalClass = [self class];

		// Traverse all classes and return early if we've already swizzled the custom subclass.
		// If its already the class, return it
		NSString *className = NSStringFromClass(originalClass);
		if (strncmp(prefix, [className UTF8String], strlen(prefix)) == 0)
			return subject;

		NSString *subclassName = [NSString stringWithFormat:@"%s%@", prefix, className];
		Class subclass = NSClassFromString(subclassName);

		// Dynamically create a subclass of self
		if (subclass == nil) {
			subclass = objc_allocateClassPair(originalClass, [subclassName UTF8String], 0);

			BOOL success = class_addIvar(subclass, "_rac_originalObject", sizeof(id), (uint8_t)log2(sizeof(id)), @encode(id));
			
			objc_registerClassPair(subclass);

			Method method = class_getInstanceMethod([NSObject class], @selector(forwardInvocation:));
			success = class_addMethod(subclass, @selector(forwardInvocation:), (IMP)RACForwardInvocation, method_getTypeEncoding(method));
			if (!success) return nil;

			method = class_getInstanceMethod([NSObject class], @selector(respondsToSelector:));
			success = class_addMethod(subclass, @selector(respondsToSelector:), (IMP)RACRespondsToSelector, method_getTypeEncoding(method));
			if (!success) return nil;

			method = class_getInstanceMethod([NSObject class], @selector(methodSignatureForSelector:));
			success = class_addMethod(subclass, @selector(methodSignatureForSelector:), (IMP)RACMethodSignatureForSelector, method_getTypeEncoding(method));
			if (!success) return nil;
		}

		IMP imp = imp_implementationWithBlock(^(id self, ...) {
			va_list args;
			va_start(args, self);

			NSMutableArray *objects = [NSMutableArray array];
			unsigned int argCount = method_getNumberOfArguments(method) - 2;
			for (unsigned int i = 0; i < argCount; i++) {
				id currentObject = va_arg(args, id);
				[objects addObject:currentObject ?: RACTupleNil.tupleNil];
			}
			va_end(args);

			[subject sendNext:[RACTuple tupleWithObjectsFromArray:objects]];
		});

		if (subclass != nil) {
			// Add block as the custom instance method.
			class_replaceMethod(subclass, selector, imp, method_getTypeEncoding(method));
		}

		if (subclass != nil) {
			object_setClass(self, subclass);
		}

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
