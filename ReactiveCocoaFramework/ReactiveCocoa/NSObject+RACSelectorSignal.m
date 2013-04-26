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


// A proxy object that intercepts messages to its target and sends the
// invocation arguments to its target's subscribers.
//
// Messages sent to an RACSelectorProxy object will be lifted according to the same
// rules as -rac_liftSelector:withObjects:, with the exception that messages
// returning a non-object type are not possible.
@interface RACSelectorProxy : NSProxy

- (id)initWithTarget:(NSObject *)target selector:(SEL)selector;

@end


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


		const char * prefix = "RACSelectorSignal_";
		Class originalClass = [self class];


		// Traverse all classes a return early if we've already swizzled the custom subclass.
		NSString *className = NSStringFromClass(originalClass);
		if (strncmp(prefix, [className UTF8String], strlen(prefix)) == 0) return subject;

		NSString * subclassName = [NSString stringWithFormat:@"%s%@", prefix, className];
		Class subclass = NSClassFromString(subclassName);

		// Dynamically create a subclass of self
		if (subclass == nil) {
			subclass = objc_allocateClassPair(originalClass, [subclassName UTF8String], 0);

			objc_registerClassPair(subclass);
		}


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

@implementation RACSelectorProxy {
	NSObject *_target;
	SEL _selector;
}

- (id)initWithTarget:(id)target selector:(SEL)selector {
	_target = target;
	_selector = selector;
	return self;
}

- (NSMethodSignature *)methodSignatureForSelector:(SEL)aSelector {
	return [_target methodSignatureForSelector:aSelector] ?: [super methodSignatureForSelector:aSelector];
}

- (void)forwardInvocation:(NSInvocation *)anInvocation {
	NSMethodSignature *signature = anInvocation.methodSignature;
	NSUInteger argumentsCount = signature.numberOfArguments - 2;

	NSMutableArray *arguments = [NSMutableArray arrayWithCapacity:argumentsCount];

	// First two arguments are self and selector.
	for (NSUInteger i = 2; i < signature.numberOfArguments; i++) {
		id argument = [anInvocation rac_argumentAtIndex:i];
		[arguments addObject:argument ?: RACTupleNil.tupleNil];
	}

	[anInvocation invoke];
	
	NSMutableDictionary *selectorSignals = objc_getAssociatedObject(self, RACObjectSelectorSignals);
	NSString *selectorString = NSStringFromSelector(_selector);
	RACSubject *selectorSignal = [selectorSignals[selectorString] first];
	if (selectorSignal)
	[selectorSignal sendNext:[arguments copy]];

	const char *returnType = signature.methodReturnType;
	if (signature.methodReturnLength > 0) {
		if (strcmp(returnType, "@") != 0 || strcmp(returnType, "#") != 0) {
			NSAssert(NO, @"-rac_signalForSelector: may only subscribe to methods which return void or object types; %@ returns %s", NSStringFromSelector(anInvocation.selector), returnType);
		}
	}
}

// Choices here are dynamically subclass the object, add the requested method if it doesn't exist yet, set the object's class to the class
// Caveats: I dont think this works if the class has already been observed. It breaks those observations?

// Set the object's class to RACSelectorProxy, forward messages to original object. Probably works.
// Caveats: Probably slow.
@end
