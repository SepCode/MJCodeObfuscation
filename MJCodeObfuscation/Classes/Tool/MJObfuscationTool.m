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
    for (NSString *subpath in subpaths) {
        !progress ? : progress([NSString stringWithFormat:@"分析：%@", subpath.lastPathComponent]);
        
        
        dispatch_group_async(group, dispatch_get_global_queue(0, 0), ^{
            
            [set addObjectsFromArray:
             [MJClangTool classesAndMethodsWithFile:subpath
                                           prefixes:prefixes
                                         searchPath:dir].allObjects];
            dispatch_semaphore_signal(sem);
        });
        
        dispatch_semaphore_wait(sem, DISPATCH_TIME_FOREVER);
    }
    
    dispatch_group_notify(group, dispatch_get_global_queue(0, 0), ^{
        !progress ? : progress(@"正在混淆...");
        NSMutableString *fileContent = [NSMutableString string];
        [fileContent appendString:@"#ifndef QYCTCodeObfuscation_h\n"];
        [fileContent appendString:@"#define QYCTCodeObfuscation_h\n"];
        NSArray *tokens = [set sortedArrayUsingDescriptors:@[[NSSortDescriptor sortDescriptorWithKey:nil ascending:YES]]];
        for (NSString *token in tokens) {
            NSString *obfuscation = @"QYCT";
            [fileContent appendFormat:@"#define %@ %@%@\n", token, obfuscation, token];
        }
        [fileContent appendString:@"#endif"];
        NSInteger time = NSDate.date.timeIntervalSince1970 - date.timeIntervalSince1970;
        !progress ? : progress([NSString stringWithFormat:@"混淆完毕! %ld:%ld", time / 60, time % 60]);
        completion(fileContent);
        
    });
    
}

@end
