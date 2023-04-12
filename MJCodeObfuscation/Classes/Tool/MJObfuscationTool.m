//
//  MJObfuscationTool.m
//  MJCodeObfuscation
//
//  Created by MJ Lee on 2018/8/17.
//  Copyright © 2018年 MJ Lee. All rights reserved.
//

#import "MJObfuscationTool.h"
#import "NSString+Extension.h"
#import "NSFileManager+Extension.h"
#import "MJClangTool.h"

#define MJEncryptKeyVar @"#var#"
#define MJEncryptKeyComment @"#comment#"
#define MJEncryptKeyFactor @"#factor#"
#define MJEncryptKeyValue @"#value#"
#define MJEncryptKeyLength @"#length#"
#define MJEncryptKeyContent @"#content#"

@implementation MJObfuscationTool

+ (NSString *)_encryptStringDataHWithComment:(NSString *)comment
                                         var:(NSString *)var
{
    NSMutableString *content = [NSMutableString string];
    [content appendString:[NSString mj_stringWithFilename:@"MJEncryptStringDataHUnit" extension:@"tpl"]];
    [content replaceOccurrencesOfString:MJEncryptKeyComment
                             withString:comment
                                options:NSCaseInsensitiveSearch range:NSMakeRange(0, content.length)];
    [content replaceOccurrencesOfString:MJEncryptKeyVar
                             withString:var
                                options:NSCaseInsensitiveSearch range:NSMakeRange(0, content.length)];
    return content;
}

+ (NSString *)_encryptStringDataMWithComment:(NSString *)comment
                                         var:(NSString *)var
                                      factor:(NSString *)factor
                                       value:(NSString *)value
                                      length:(NSString *)length
{
    NSMutableString *content = [NSMutableString mj_stringWithFilename:@"MJEncryptStringDataMUnit"
                                                            extension:@"tpl"];
    [content replaceOccurrencesOfString:MJEncryptKeyComment
                             withString:comment
                                options:NSCaseInsensitiveSearch range:NSMakeRange(0, content.length)];
    [content replaceOccurrencesOfString:MJEncryptKeyVar
                             withString:var
                                options:NSCaseInsensitiveSearch range:NSMakeRange(0, content.length)];
    [content replaceOccurrencesOfString:MJEncryptKeyFactor
                             withString:factor
                                options:NSCaseInsensitiveSearch range:NSMakeRange(0, content.length)];
    [content replaceOccurrencesOfString:MJEncryptKeyValue
                             withString:value
                                options:NSCaseInsensitiveSearch range:NSMakeRange(0, content.length)];
    [content replaceOccurrencesOfString:MJEncryptKeyLength
                             withString:length
                                options:NSCaseInsensitiveSearch range:NSMakeRange(0, content.length)];
    return content;
}

+ (void)encryptString:(NSString *)string
                 completion:(void (^)(NSString *, NSString *))completion
{
    if (string.mj_stringByRemovingSpace.length == 0
        || !completion) return;
    
    // 拼接value
    NSMutableString *value = [NSMutableString string];
    char factor = arc4random_uniform(pow(2, sizeof(char) * 8) - 1);
    const char *cstring = string.UTF8String;
    int length = (int)strlen(cstring);
    for (int i = 0; i< length; i++) {
        [value appendFormat:@"%d,", factor ^ cstring[i]];
    }
    [value appendString:@"0"];
    
    // 变量
    NSString *var = [NSString stringWithFormat:@"_%@", string.mj_crc32];
    
    // 注释
    NSMutableString *comment = [NSMutableString string];
    [comment appendFormat:@"/* %@ */", string];
    
    // 头文件
    NSString *hStr = [self _encryptStringDataHWithComment:comment var:var];
    
    // 源文件
    NSString *mStr = [self _encryptStringDataMWithComment:comment
                                                      var:var
                                                   factor:[NSString stringWithFormat:@"%d", factor]
                                                    value:value
                                                   length:[NSString stringWithFormat:@"%d", length]];
    completion(hStr, mStr);
}

+ (void)encryptStringsAtDir:(NSString *)dir
                         progress:(void (^)(NSString *))progress
                       completion:(void (^)(NSString *, NSString *))completion
{
    if (dir.length == 0 || !completion) return;
    
    !progress ? : progress(@"正在扫描目录...");
    NSArray *subpaths = [NSFileManager mj_subpathsAtPath:dir
                                              extensions:@[@"c", @"cpp", @"m", @"mm"]];
    
    NSMutableSet *set = [NSMutableSet set];
    for (NSString *subpath in subpaths) {
        !progress ? : progress([NSString stringWithFormat:@"分析：%@", subpath.lastPathComponent]);
        [set addObjectsFromArray:[MJClangTool stringsWithFile:subpath
                                                   searchPath:dir].allObjects];
    }
    
    !progress ? : progress(@"正在加密...");
    NSMutableString *hs = [NSMutableString string];
    NSMutableString *ms = [NSMutableString string];
    
    int index = 0;
    for (NSString *string in set) {
        index++;
        [self encryptString:string completion:^(NSString *h, NSString *m) {
            [hs appendFormat:@"%@", h];
            [ms appendFormat:@"%@", m];
            
            if (index != set.count) {
                [hs appendString:@"\n"];
                [ms appendString:@"\n"];
            }
        }];
    }
    
    !progress ? : progress(@"加密完毕!");
    
    NSMutableString *hFileContent = [NSMutableString mj_stringWithFilename:@"MJEncryptStringDataH" extension:@"tpl"];
    [hFileContent replaceOccurrencesOfString:MJEncryptKeyContent withString:hs options:NSCaseInsensitiveSearch range:NSMakeRange(0, hFileContent.length)];
    NSMutableString *mFileContent = [NSMutableString mj_stringWithFilename:@"MJEncryptStringDataM" extension:@"tpl"];
    [mFileContent replaceOccurrencesOfString:MJEncryptKeyContent withString:ms options:NSCaseInsensitiveSearch range:NSMakeRange(0, mFileContent.length)];
    completion(hFileContent, mFileContent);
}

+ (void)obfuscateWhiteList:(NSMutableSet *)tokens categorys:(NSMutableSet *)categorys {
    tokensWhiteList = tokens;
    categorysWhiteList = categorys;
}

+ (void)obfuscateAtDir:(NSString *)dir
                    prefixes:(NSArray *)prefixes
                    progress:(void (^)(NSString *))progress
                  completion:(void (^)(NSString *))completion
{
    if (dir.length == 0 || !completion) return;
    NSDate *date = NSDate.date;
    !progress ? : progress(@"正在扫描目录...");
    NSArray *subpaths = [NSFileManager mj_subpathsAtPath:dir extensions:@[@"h", @"m", @"mm"]];
    
    dispatch_group_t group = dispatch_group_create();
    dispatch_semaphore_t sem = dispatch_semaphore_create(10);
    
    NSMutableSet *set = [NSMutableSet set];
    NSMutableSet *set1 = [NSMutableSet set];
    for (NSString *subpath in subpaths) {
        !progress ? : progress([NSString stringWithFormat:@"分析：%@", subpath.lastPathComponent]);
        
        
        dispatch_group_async(group, dispatch_get_global_queue(0, 0), ^{
            NSArray <NSSet *>*data = [MJClangTool classesAndMethodsWithFile:subpath
                                                          prefixes:prefixes
                                                        searchPath:dir];
            [set addObjectsFromArray:data[0].allObjects];
            [set1 addObjectsFromArray:data[1].allObjects];
            dispatch_semaphore_signal(sem);
        });
        
        dispatch_semaphore_wait(sem, DISPATCH_TIME_FOREVER);
    }
    
    dispatch_group_notify(group, dispatch_get_global_queue(0, 0), ^{
        !progress ? : progress(@"正在混淆...");
        NSMutableString *fileContent = [NSMutableString string];
        NSString *obfuscation = @"";
        if (prefixes.count > 0) {
            obfuscation = prefixes[0];
        }
        [fileContent appendString:[NSString stringWithFormat:@"#ifndef %@CodeObfuscation_h\n", obfuscation]];
        [fileContent appendString:[NSString stringWithFormat:@"#define %@CodeObfuscation_h\n", obfuscation]];
        
        NSArray *sort = @[[NSSortDescriptor sortDescriptorWithKey:nil ascending:YES]];
        // 类名，static变量，枚举，协议，typedef 处理QYCT...
        NSArray *tokens = [set sortedArrayUsingDescriptors:sort];
        for (NSString *token in tokens) {
            [fileContent appendFormat:@"#define %@ %@%@\n", token, obfuscation, token];
        }
        // 分类处理..._QYCT
        NSArray *categorys = [set1 sortedArrayUsingDescriptors:sort];
        for (NSString *category in categorys) {
            [fileContent appendFormat:@"#define %@ %@_%@\n", category, category, obfuscation];
        }
        [fileContent appendString:@"#endif"];
        NSInteger time = NSDate.date.timeIntervalSince1970 - date.timeIntervalSince1970;
        !progress ? : progress([NSString stringWithFormat:@"混淆完毕! %ld:%ld", time / 60, time % 60]);
        completion(fileContent);
        
    });
    
}

@end
