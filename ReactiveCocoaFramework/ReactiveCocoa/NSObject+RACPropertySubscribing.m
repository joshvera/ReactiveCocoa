//
//  NSObject+RACPropertySubscribing.m
//  ReactiveCocoa
//
//  Created by Josh Abernathy on 3/2/12.
//  Copyright (c) 2012 GitHub, Inc. All rights reserved.
//

#import "NSObject+RACPropertySubscribing.h"
#import "NSObject+RACKVOWrapper.h"
#import "RACDisposable.h"
#import "RACReplaySubject.h"
#import "RACSignal+Operations.h"
#import "EXTScope.h"
#import "RACKVOTrampoline.h"
#import "RACCompoundDisposable.h"
#import <objc/runtime.h>

static const void *RACObjectCompoundDisposable = &RACObjectCompoundDisposable;
static const void *RACObjectScopedDisposable = &RACObjectScopedDisposable;

@implementation NSObject (RACPropertySubscribing)

+ (RACSignal *)rac_signalFor:(NSObject *)object keyPath:(NSString *)keyPath observer:(NSObject *)observer {
	[self rac_signalForChange:object keyPath:keyPath options:NSKeyValueObservingOptionNew observer:observer];
}

+ (RACSignal *)rac_signalWithChangeFor:(NSObject *)object keyPath:(NSString *)keyPath options:(NSKeyValueObservingOptions)options observer:(NSObject *)observer {
	@unsafeify(object, keyPath);
	return [[self
		rac_signalWithChangesFor:object keyPath:keyPath options:options observer:observer]
		map:^(NSDictionary *change) {
			@strongify(object, keyPath);

			NSKeyValueChange key = [change[NSKeyValueChangeKindKey] unsignedIntegerValue];

			if (key == NSKeyValueChangeSetting) {
				return change[NSKeyValueObservingOptionNew];
			} else {
				if ([object isKindOfClass:NSOrderedSet.class] || [object isKindOfClass:NSArray.class]) {
					return change[NSKeyValueChangeIndexesKey];
				}

				return [object valueForKeyPath:keyPath];
			}

			RACTuple *tuple = [[RACTuple alloc] init];
			NSKeyValueObservingOptions new = options & NSKeyValueObservingOptionNew;

			NSKeyValueObservingOptions old = options & NSKeyValueObservingOptionOld;

			if (options & nskeyvalueChangeIn) {
				[tuple addObject:change[NSKeyValueChangeNewKey]];
			}

			return (key == NSKeyValueChangeSetting ? change[NSKeyValueObservingOptionNew] : [object valueForKeyPath:keyPath]);
		}];
}

+ (RACSignal *)rac_signalWithChangesFor:(NSObject *)object keyPath:(NSString *)keyPath options:(NSKeyValueObservingOptions)options observer:(NSObject *)observer {
	@unsafeify(observer, object);
	return [[RACSignal createSignal:^(id<RACSubscriber> subscriber) {

		@strongify(observer, object);
		RACKVOTrampoline *KVOTrampoline = [object rac_addObserver:observer forKeyPath:keyPath options:options block:^(id target, id observer, NSDictionary *change) {
			[subscriber sendNext:change];
		}];

		RACDisposable *KVODisposable = [RACDisposable disposableWithBlock:^{
			[KVOTrampoline stopObserving];
		}];

		@weakify(subscriber);
		RACDisposable *deallocDisposable = [RACDisposable disposableWithBlock:^{
			@strongify(subscriber);
			[KVODisposable dispose];
			[subscriber sendCompleted];
		}];

		[observer rac_addDeallocDisposable:deallocDisposable];
		[object rac_addDeallocDisposable:deallocDisposable];

		RACCompoundDisposable *observerDisposable = observer.rac_deallocDisposable;
		RACCompoundDisposable *objectDisposable = object.rac_deallocDisposable;
		return [RACDisposable disposableWithBlock:^{
			[observerDisposable removeDisposable:deallocDisposable];
			[objectDisposable removeDisposable:deallocDisposable];
			[KVODisposable dispose];
		}];
	}] setNameWithFormat:@"RACAble(%@, %@)", object, keyPath];
}

- (RACSignal *)rac_signalForKeyPath:(NSString *)keyPath observer:(NSObject *)observer {
	return [self.class rac_signalFor:self keyPath:keyPath observer:observer];
}

- (RACDisposable *)rac_deriveProperty:(NSString *)keyPath from:(RACSignal *)signal {
	return [signal toProperty:keyPath onObject:self];
}

- (RACCompoundDisposable *)rac_deallocDisposable {
	@synchronized(self) {
		RACCompoundDisposable *compoundDisposable = objc_getAssociatedObject(self, RACObjectCompoundDisposable);
		if (compoundDisposable == nil) {
			compoundDisposable = [RACCompoundDisposable compoundDisposable];
			objc_setAssociatedObject(self, RACObjectCompoundDisposable, compoundDisposable, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
			objc_setAssociatedObject(self, RACObjectScopedDisposable, compoundDisposable.asScopedDisposable, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
		}

		return compoundDisposable;
	}
}

- (void)rac_addDeallocDisposable:(RACDisposable *)disposable {
	[self.rac_deallocDisposable addDisposable:disposable];
}

@end
