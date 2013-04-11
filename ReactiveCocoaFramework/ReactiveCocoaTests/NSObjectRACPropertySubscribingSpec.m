//
//  NSObjectRACPropertySubscribingSpec.m
//  ReactiveCocoa
//
//  Created by Josh Abernathy on 9/28/12.
//  Copyright (c) 2012 GitHub, Inc. All rights reserved.
//

#import "NSObject+RACPropertySubscribing.h"
#import "NSObjectRACPropertySubscribingExamples.h"
#import "RACDisposable.h"
#import "RACTestObject.h"
#import "RACSignal.h"

SpecBegin(NSObjectRACPropertySubscribing)

describe(@"RACAble", ^{
	it(@"lol", ^{
		RACTestObject *object = [[RACTestObject alloc] init];
		__block id actual;
		[RACAble(object, objectValue, NSKeyValueObservingOptionNew) subscribeNext:^(id _) {
			actual = _;
		}];

		object.objectValue = @1;

		expect(actual).to.beKindOf(NSDictionary.class);
	});
});

describe(@"-rac_addDeallocDisposable:", ^{
	it(@"should dispose of the disposable when it is dealloc'd", ^{
		__block BOOL wasDisposed = NO;
		@autoreleasepool {
			NSObject *object __attribute__((objc_precise_lifetime)) = [[NSObject alloc] init];
			[object rac_addDeallocDisposable:[RACDisposable disposableWithBlock:^{
				wasDisposed = YES;
			}]];

			expect(wasDisposed).to.beFalsy();
		}

		expect(wasDisposed).to.beTruthy();
	});
});

describe(@"+rac_signalFor:keyPath:observer:", ^{

	id (^setupBlock)(id, id, id) = ^(RACTestObject *object, NSString *keyPath, id observer) {
		return [object.class rac_signalFor:object keyPath:keyPath observer:observer];
	};

	itShouldBehaveLike(RACPropertySubscribingExamples, ^{
		return @{ RACPropertySubscribingExamplesSetupBlock: setupBlock };
	});

	describe(@"KVO options argument", ^{
		__block RACTestObject *object;
		__block NSMutableOrderedSet *actual;
		__block NSMutableOrderedSet *objectValue;

		before(^{
			object = [[RACTestObject alloc] init];
			object.objectValue = [NSMutableOrderedSet orderedSetWithObject:@1];

			NSString *keyPath = @keypath(object, objectValue);

			[setupBlock(object, keyPath, self) subscribeNext:^(NSMutableOrderedSet *_) {
				actual = _;
			}];

			objectValue = [object mutableOrderedSetValueForKey:keyPath];
		});

		it(@"sends the newest object when inserting values into an observed object", ^{
			NSMutableOrderedSet *expected = [NSMutableOrderedSet orderedSetWithObjects: @1, @2, nil];

			[objectValue addObject:@2];
			expect(actual).to.equal(expected);
		});

		it(@"sends the newest object when removing values in an observed object", ^{
			NSMutableOrderedSet *expected = [NSMutableOrderedSet orderedSet];

			[objectValue removeAllObjects];
			expect(actual).to.equal(expected);
		});

		it(@"sends the newest object when replacing values in an observed object", ^{
			NSMutableOrderedSet *expected = [NSMutableOrderedSet orderedSetWithObjects: @2, nil];

			[objectValue replaceObjectAtIndex:0 withObject:@2];
			expect(actual).to.equal(expected);
		});
	});
});

describe(@"+rac_signalWithChangesFor:keyPath:options:observer:", ^{
	itShouldBehaveLike(RACPropertySubscribingExamples, @{
		RACPropertySubscribingExamplesSetupBlock: ^(RACTestObject *object, NSString *keyPath, id observer) {

			return [[object.class
				rac_signalWithChangesFor:object keyPath:keyPath options:NSKeyValueObservingOptionNew observer:observer]
				map:^(NSDictionary *change) {
					return change[NSKeyValueChangeNewKey];
				}];
		}
	});

	describe(@"KVO options argument", ^{
		__block RACTestObject *object;
		__block id actual;
		__block RACSignal *(^objectValueSignal)(NSKeyValueObservingOptions);

		before(^{
			object = [[RACTestObject alloc] init];

			objectValueSignal = ^(NSKeyValueObservingOptions options) {
				return [object.class rac_signalWithChangesFor:object keyPath:@keypath(object, objectValue) options:options observer:self];
			};
		});

		it(@"sends a KVO dictionary", ^{
			[objectValueSignal(0) subscribeNext:^(NSDictionary *x) {
				actual = x;
			}];

			object.objectValue = @1;

			expect(actual).to.beKindOf(NSDictionary.class);
		});

		it(@"sends a kind key by default", ^{
			[objectValueSignal(0) subscribeNext:^(NSDictionary *x) {
				actual = x[NSKeyValueChangeKindKey];
			}];

			object.objectValue = @1;

			expect(actual).to.beTruthy();
		});

		it(@"sends the newest changes with NSKeyValueObservingOptionNew", ^{
			[objectValueSignal(NSKeyValueObservingOptionNew) subscribeNext:^(NSDictionary *x) {
				actual = x[NSKeyValueChangeNewKey];
			}];

			object.objectValue = @1;
			expect(actual).to.equal(@1);

			object.objectValue = @2;
			expect(actual).to.equal(@2);
		});

		it(@"sends an additional change value with NSKeyValueObservingOptionPrior", ^{
			NSMutableOrderedSet *values = [NSMutableOrderedSet orderedSet];
			NSMutableOrderedSet *expected = [NSMutableOrderedSet orderedSetWithObjects:@(YES), @(NO), nil];

			[objectValueSignal(NSKeyValueObservingOptionPrior) subscribeNext:^(NSDictionary *x) {
				BOOL isPrior = [x[NSKeyValueChangeNotificationIsPriorKey] boolValue];
				[values addObject:@(isPrior)];
			}];

			object.objectValue = [NSMutableOrderedSet orderedSetWithObject:@1];

			expect(values).to.equal(expected);
		});

		it(@"sends index changes when adding, inserting or removing a value from an observed object", ^{
			__block NSUInteger hasIndexesCount = 0;

			[objectValueSignal(0) subscribeNext:^(NSDictionary *x) {
				if (x[NSKeyValueChangeIndexesKey] != nil) {
					hasIndexesCount += 1;
				}
			}];

			object.objectValue = [NSMutableOrderedSet orderedSet];
			expect(hasIndexesCount).to.equal(0);

			NSMutableOrderedSet *objectValue = [object mutableOrderedSetValueForKey:@"objectValue"];

			[objectValue addObject:@1];
			expect(hasIndexesCount).to.equal(1);

			[objectValue replaceObjectAtIndex:0 withObject:@2];
			expect(hasIndexesCount).to.equal(2);

			[objectValue removeObject:@2];
			expect(hasIndexesCount).to.equal(3);
		});

		it(@"sends the previous value with NSKeyValueObservingOptionOld", ^{
			[objectValueSignal(NSKeyValueObservingOptionOld) subscribeNext:^(NSDictionary *x) {
				actual = x[NSKeyValueChangeOldKey];
			}];

			object.objectValue = @1;
			expect(actual).to.equal(NSNull.null);

			object.objectValue = @2;
			expect(actual).to.equal(@1);
		});

		it(@"sends the initial value with NSKeyValueObservingOptionInitial", ^{
			[objectValueSignal(NSKeyValueObservingOptionInitial | NSKeyValueObservingOptionNew) subscribeNext:^(NSDictionary *x) {
				actual = x[NSKeyValueChangeNewKey];
			}];

			expect(actual).to.equal(NSNull.null);
		});
	});
});

SpecEnd
