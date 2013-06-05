//
//  NSObjectRACSelectorSignal.m
//  ReactiveCocoa
//
//  Created by Josh Abernathy on 3/18/13.
//  Copyright (c) 2013 GitHub, Inc. All rights reserved.
//

#import "RACTestObject.h"
#import "RACSubclassObject.h"
#import "NSObject+RACPropertySubscribing.h"
#import "NSObject+RACSelectorSignal.h"
#import "RACSignal.h"
#import "RACTuple.h"

SpecBegin(NSObjectRACSelectorSignal)
// Stop observing
// Swizzle Class
// Start observing
// Caveats: only works on our own observations

// Swizzle class
// Swizzle removeObserver:keyPath:context:
// Swizzle class back and call super if not RACKVOTrampoline context

describe(@"with an instance method", ^{
	it(@"should send the argument for each invocation", ^{
		RACSubclassObject *object = [[RACSubclassObject alloc] init];
		__block id value;
		[[object rac_signalForSelector:@selector(lifeIsGood:)] subscribeNext:^(RACTuple *x) {
			value = x.first;
		}];

		[object lifeIsGood:@42];

		expect(value).to.equal(@42);
	});

	it(@"should send the arguments to each subscription on the same object", ^{
		RACSubclassObject *object = [[RACSubclassObject alloc] init];
		__block id value;
		__block id value2;
		[[object rac_signalForSelector:@selector(lifeIsGood:)] subscribeNext:^(RACTuple *x) {
			value = x.first;
		}];

		[[object rac_signalForSelector:@selector(lifeIsGood:)] subscribeNext:^(RACTuple *x) {
			value2 = x.first;
		}];

		[object lifeIsGood:@42];
		
		expect(value).to.equal(@42);
		expect(value2).to.equal(@42);
	});

	it(@"should send the arguments to each subscription on a KVO observed object", ^{
		RACSubclassObject *object = [[RACSubclassObject alloc] init];
		__block id value;

		[RACAbleWithStart(object, objectValue) subscribeNext:^(id _) {

		}];

		[[object rac_signalForSelector:@selector(lifeIsGood:)] subscribeNext:^(RACTuple *x) {
			value = x.first;
		}];

		[object lifeIsGood:@42];
		
		expect(value).to.equal(@42);
	});

	it(@"should send the arguments for each invocation to the associated signal", ^{
		RACSubclassObject *object1 = [[RACSubclassObject alloc] init];
		__block id value1;
		[[object1 rac_signalForSelector:@selector(lifeIsGood:)] subscribeNext:^(RACTuple *x) {
			value1 = x.first;
		}];

		RACSubclassObject *object2 = [[RACSubclassObject alloc] init];
		__block id value2;
		[[object2 rac_signalForSelector:@selector(lifeIsGood:)] subscribeNext:^(RACTuple *x) {
			value2 = x.first;
		}];

		[object1 lifeIsGood:@42];
		[object2 lifeIsGood:@"Carpe diem"];

		expect(value1).to.equal(@42);
		expect(value2).to.equal(@"Carpe diem");
	});

	it(@"should send all arguments for each invocation", ^{
		RACSubclassObject *object = [[RACSubclassObject alloc] init];
		__block id value1;
		__block id value2;
		[[object rac_signalForSelector:@selector(combineObjectValue:andSecondObjectValue:)] subscribeNext:^(RACTuple *x) {
			value1 = x.first;
			value2 = x.second;
		}];

		[object combineObjectValue:@42 andSecondObjectValue:@"foo"];

		expect(value1).to.equal(@42);
		expect(value2).to.equal(@"foo");
	});

	it(@"should create method where non-existent", ^{
		RACSubclassObject *object = [[RACSubclassObject alloc] init];
		__block id value;
		[[object rac_signalForSelector:@selector(setDelegate:)] subscribeNext:^(RACTuple *x) {
			value = x.first;
		}];

		[object performSelector:@selector(setDelegate:) withObject:@[ @YES ]];

		expect(value).to.equal(@[ @YES ]);
	});
});

describe(@"with a class method", ^{
	it(@"should send the argument for each invocation", ^{
		__block id value;
		[[RACSubclassObject rac_signalForSelector:@selector(lifeIsGood:)] subscribeNext:^(RACTuple *x) {
			value = x.first;
		}];

		[RACSubclassObject lifeIsGood:@42];

		expect(value).to.equal(@42);
	});

	it(@"should send the argument for each invocation to the associated signal", ^{
		__block id value1;
		[[RACTestObject rac_signalForSelector:@selector(lifeIsGood:)] subscribeNext:^(RACTuple *x) {
			value1 = x.first;
		}];

		__block id value2;
		[[RACSubclassObject rac_signalForSelector:@selector(lifeIsGood:)] subscribeNext:^(RACTuple *x) {
			value2 = x.first;
		}];

		[RACTestObject lifeIsGood:@42];
		[RACSubclassObject lifeIsGood:@"Carpe diem"];

		expect(value1).to.equal(@42);
		expect(value2).to.equal(@"Carpe diem");
	});

	it(@"should send all arguments for each invocation", ^{
		__block id value1;
		__block id value2;
		[[RACSubclassObject rac_signalForSelector:@selector(combineObjectValue:andSecondObjectValue:)] subscribeNext:^(RACTuple *x) {
			value1 = x.first;
			value2 = x.second;
		}];

		[RACSubclassObject combineObjectValue:@42 andSecondObjectValue:@"foo"];

		expect(value1).to.equal(@42);
		expect(value2).to.equal(@"foo");
	});

	it(@"should create method where non-existent", ^{
		__block id value;
		[[RACSubclassObject rac_signalForSelector:@selector(setDelegate:)] subscribeNext:^(RACTuple *x) {
			value = x.first;
		}];

		[RACSubclassObject performSelector:@selector(setDelegate:) withObject:@[ @YES ]];

		expect(value).to.equal(@[ @YES ]);
	});
});

SpecEnd
