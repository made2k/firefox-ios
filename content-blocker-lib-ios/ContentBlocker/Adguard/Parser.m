//
//  Parser.m
//  TestAdguardParsing
//
//  Created by Zach McGaughey on 10/14/18.
//  Copyright © 2018 Mozilla. All rights reserved.
//

#import "Parser.h"
#import <JavaScriptCore/JavaScriptCore.h>

#define JS_CONVERTER_FILE       @"JSConverter.js"
#define JS_CONVERTER_FUNC       @"jsonFromFilters"

@interface Parser (){

    JSContext *_context;
    JSValue *_converterFunc;
}
@end

@implementation Parser

- (Parser *)init{

    self = [super init];
    if (self) {

        _context = [[JSContext alloc] init]; //WithVirtualMachine:[JSVirtualMachine new]];
        if (!_context) {
            NSLog(@"Can't init jscontext");
            return nil;
        }

        NSString *script;
        NSURL *url = [[[NSBundle bundleForClass:[self class]] resourceURL] URLByAppendingPathComponent:JS_CONVERTER_FILE];
        if (url) {
            script = [NSString stringWithContentsOfURL:url encoding:NSUTF8StringEncoding error:NULL];
        }
        if (!script) {
            NSLog(@"(AESFilterConverter) Can't load javascript file: %@", url);
            return nil;
        }

        [_context evaluateScript:@"var console = {}"];
        _context[@"console"][@"log"] = ^(NSString *message) {
            NSLog(@"Javascript: %@",message);
        };
        _context[@"console"][@"warn"] = ^(NSString *message) {
            NSLog(@"Javascript Warn: %@",message);
        };
        _context[@"console"][@"info"] = ^(NSString *message) {
            NSLog(@"Javascript Info: %@",message);
        };
        _context[@"console"][@"error"] = ^(NSString *message) {
            NSLog(@"Javascript Error: %@",message);
        };

        _context[@"window"] = _context.globalObject;

        [_context evaluateScript:script];
        _converterFunc = _context[JS_CONVERTER_FUNC];
        if (!_converterFunc || [_converterFunc isUndefined]) {
            NSLog(@"(AESFilterConverter) Can't obtain converter function object: %@", JS_CONVERTER_FUNC);
            return nil;
        }
#ifdef DEBUG
        else{
            NSLog(@"ConvertFunction: \n%@", [_converterFunc toString]);
        }
#endif
    }
    return self;
}

- (NSDictionary *)jsonFromRules:(NSArray *)rules upTo:(NSUInteger)limit optimize:(BOOL)optimize {

    if (!(rules.count && limit)) {
        return nil;
    }

    @autoreleasepool {

        NSMutableArray *_rules = [NSMutableArray arrayWithCapacity:rules.count];
        NSMutableSet *ruleTextSet = [NSMutableSet set];
        for (NSString *rule in rules) {
            // This should delete duplicates.
            if (![ruleTextSet containsObject:rule]) {

                [ruleTextSet addObject:rule];
                //--------------
                [_rules addObject:rule];
            }
        }

        JSValue *result = [_converterFunc callWithArguments:@[ _rules, @(limit), @(optimize)]];

        NSDictionary *dictResult = [result toDictionary];
        return dictResult;
    }
}

@end
