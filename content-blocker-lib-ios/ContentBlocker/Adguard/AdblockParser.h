//
//  AdblockParser.h
//  Client
//
//  Created by Zach McGaughey on 4/1/19.
//  Copyright © 2019 Mozilla. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface AdblockParser : NSObject

- (NSDictionary *)jsonFromRules:(NSArray *)rules upTo:(NSUInteger)limit optimize:(BOOL)optimize;

@end

NS_ASSUME_NONNULL_END
