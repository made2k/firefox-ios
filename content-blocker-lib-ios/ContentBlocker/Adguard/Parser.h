//
//  Parser.h
//  Client
//
//  Created by Zach McGaughey on 10/14/18.
//  Copyright © 2018 Mozilla. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface Parser : NSObject

- (NSDictionary *)jsonFromRules:(NSArray *)rules upTo:(NSUInteger)limit optimize:(BOOL)optimize;

@end

NS_ASSUME_NONNULL_END
