//
//  MJObfuscationTool.h
//  MJCodeObfuscation
//
//  Created by MJ Lee on 2018/8/17.
//  Copyright © 2018年 MJ Lee. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface MJObfuscationTool : NSObject

/** 加密字符串 */
+ (void)encryptString:(NSString *)string
           completion:(void (^)(NSString *h, NSString *m))completion;

/** 加密dir下的所有字符串 */
+ (void)encryptStringsAtDir:(NSString *)dir
                   progress:(void (^)(NSString *detail))progress
                 completion:(void (^)(NSString *h, NSString *m))completion;


/// 添加白名单
/// - Parameters:
///   - tokens: 类名，static变量，枚举，协议，typedef
///   - categorys: 分类的方法，属性
+ (void)obfuscateWhiteList:(NSMutableSet *)tokens categorys:(NSMutableSet *)categorys;

/** 混淆dir下的所有类名、方法名 */
+ (void)obfuscateAtDir:(NSString *)dir
              prefixes:(NSArray *)prefixes
              progress:(void (^)(NSString *detail))progress
            completion:(void (^)(NSString *fileContent))completion;

@end
