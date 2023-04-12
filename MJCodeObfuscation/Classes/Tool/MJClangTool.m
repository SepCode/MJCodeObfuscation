//
//  MJClangTool.m
//  MJCodeObfuscation
//
//  Created by MJ Lee on 2018/8/17.
//  Copyright © 2018年 MJ Lee. All rights reserved.
//

#import "MJClangTool.h"
#import "clang-c/Index.h"
#import "NSFileManager+Extension.h"
#import "NSString+Extension.h"
#import <JavaScriptCore/JavaScriptCore.h>
#import <objc/runtime.h>

NSMutableSet *tokensWhiteList;
NSMutableSet *categorysWhiteList;

/** 类名、方法名 */
@interface MJTokensClientData : NSObject
@property (nonatomic, strong) NSArray *prefixes;
@property (nonatomic, strong) NSMutableSet *tokens;
@property (nonatomic, strong) NSMutableSet *categorys;

@property (nonatomic, strong) NSMutableSet *tokensWhiteList;
@property (nonatomic, strong) NSMutableSet *categorysWhiteList;
@property (nonatomic, copy) NSString *file;
@end

@implementation MJTokensClientData
@end

/** 字符串 */
@interface MJStringsClientData : NSObject
@property (nonatomic, strong) NSMutableSet *strings;
@property (nonatomic, copy) NSString *file;
@end

@implementation MJStringsClientData
@end

@implementation MJClangTool

static const char *_getFilename(CXCursor cursor) {
    CXSourceRange range = clang_getCursorExtent(cursor);
    CXSourceLocation location = clang_getRangeStart(range);
    CXFile file;
    clang_getFileLocation(location, &file, NULL, NULL, NULL);
    return clang_getCString(clang_getFileName(file));
}

static const char *_getCursorName(CXCursor cursor) {
    return clang_getCString(clang_getCursorSpelling(cursor));
}

static const char *_getCursorUSR(CXCursor cursor) {
    return clang_getCString(clang_getCursorUSR(cursor));
}

static bool _isFromFile(const char *filepath, CXCursor cursor) {
    if (filepath == NULL) return 0;
    const char *cursorPath = _getFilename(cursor);
    if (cursorPath == NULL) return 0;
    NSString *fpath = [NSString stringWithUTF8String:filepath].stringByDeletingPathExtension;
    NSString *cpath = [NSString stringWithUTF8String:cursorPath].stringByDeletingPathExtension;
    
    return [fpath isEqualToString:cpath];
}

static bool _isFromFileName(const char *filepath, const char *cursorPath) {
    if (filepath == NULL) return 0;
    if (cursorPath == NULL) return 0;
    NSString *fpath = [NSString stringWithUTF8String:filepath].stringByDeletingPathExtension;
    NSString *cpath = [NSString stringWithUTF8String:cursorPath].stringByDeletingPathExtension;
    
    return [fpath isEqualToString:cpath];
}

bool isStaticExternConst(CXCursor cursor) {
    if (clang_getCursorKind(cursor) != CXCursor_VarDecl) {
        return false;
    }
    CXType type = clang_getCursorType(cursor);
    if (!clang_isConstQualifiedType(type)) {
        return false;
    }
    enum CX_StorageClass storage = clang_Cursor_getStorageClass(cursor);
    if (!(storage == CX_SC_Static || storage == CX_SC_Extern)) {
        return false;
    }
    return true;
}

extern const char* _dyld_get_objc_selector(const char* selName);

enum CXChildVisitResult _visitTokens(CXCursor cursor,
                                      CXCursor parent,
                                      CXClientData clientData) {
    if (clientData == NULL) return CXChildVisit_Break;
    
    MJTokensClientData *data = (__bridge MJTokensClientData *)clientData;
    const char *cursorPath = _getFilename(cursor);
    if (!_isFromFileName(data.file.UTF8String, cursorPath)) return CXChildVisit_Continue;
    
    
    
    // 分类的类对象可以找到，clang_getCursorUSR有返回，找不到时clang_getCursorUSR为空
    // 分类的usr为 c:objc(cy) ，扩展的usr为 c:objc(ext)
    // 分类的clang_getCursorSpelling 有值，扩展没有值
    // 分类的类可以通过bundleForClass是否是mainBundle进行判断
    // 分类的类如果是系统类，属性名和方法需要改名，不是系统类如果能找到，不需要改名，找不到需要改名。
    
    // 分类或者扩展
    if (parent.kind == CXCursor_ObjCCategoryDecl || parent.kind == CXCursor_ObjCCategoryImplDecl) {
        NSString *usr = [NSString stringWithUTF8String:_getCursorUSR(parent)];
        
        // 有类的分类或扩展
        if (usr.length > 0) {
            NSString *cy = @"c:objc(cy)";
            if ([usr hasPrefix:cy]) { // 分类
                NSArray <NSString *>*usrs = [usr componentsSeparatedByString:@"@"];
                NSString *name = [usrs.firstObject substringFromIndex:cy.length];
                
                // 非系统类的分类不需要处理 不处理类名白名单
                if ([data.tokensWhiteList containsObject:name]) {
                    return CXChildVisit_Continue;
                }
                
            } else {
                // 扩展不需要处理（扩展通常和类写在一起）
                return CXChildVisit_Continue;
            }
        }
        
        // 找不到类的分类，系统类的分类需要处理
        const char *cname = _getCursorName(cursor);
        NSString *name = [NSString stringWithUTF8String:cname];
        NSArray <NSString *>*sels = [name componentsSeparatedByString:@":"];
        
        if (cursor.kind == CXCursor_ObjCClassMethodDecl || // 类方法
            cursor.kind == CXCursor_ObjCInstanceMethodDecl // 实例方法
            ) {
            NSLog(@"---categorys file: %@ ---method: %s", [NSString stringWithUTF8String:cursorPath].lastPathComponent, cname);
            // 系统SEL
            const char *selector = _dyld_get_objc_selector(cname);
            if (selector != NULL) {
                return CXChildVisit_Continue;
            }
            
            for (NSString *sel in sels) {
                const char *selector = _dyld_get_objc_selector(sel.UTF8String);
                if (selector == NULL && sel.length && ![data.categorysWhiteList containsObject:sel]) { // 不处理方法白名单
                    [data.categorys addObject:sel];
                    return CXChildVisit_Continue;
                } else {
                    NSLog(@"---categorys file: %@ ---method selector: %@ ❌", [NSString stringWithUTF8String:cursorPath].lastPathComponent, sel);
                }
            }
            
        } else if (cursor.kind == CXCursor_ObjCPropertyDecl // 属性
                   ) {
            NSLog(@"---categorys file: %@ ---property: %s", [NSString stringWithUTF8String:cursorPath].lastPathComponent, cname);

            NSString *token = sels.firstObject;
            if (token.length) {
                [data.categorys addObject:token];
                return CXChildVisit_Continue;
            }
        }
        
        // log系统或者非系统类的类名
        NSLog(@"---categorys file: %@ ---class: %@", [NSString stringWithUTF8String:cursorPath].lastPathComponent, name);
        
    } else if (cursor.kind == CXCursor_EnumConstantDecl ||//常量枚举
        cursor.kind == CXCursor_ObjCInterfaceDecl ||// 声明
        cursor.kind == CXCursor_ObjCProtocolDecl ||// 协议
        cursor.kind == CXCursor_ObjCImplementationDecl ||// 实现
        cursor.kind == CXCursor_EnumDecl ||// 枚举
        isStaticExternConst(cursor) // static or extern const var
        ) {
        NSString *name = [NSString stringWithUTF8String:_getCursorName(cursor)];
        NSString *token = [name componentsSeparatedByString:@":"].firstObject;
        if (token.length) {
            if (cursor.kind == CXCursor_TypedefDecl // Typedef
                ) { // 使用后缀
                [data.categorys addObject:token];
            } else {
                [data.tokens addObject:token];
            }
        }
    }
    
    return CXChildVisit_Recurse;
}

void diagnostic(CXClientData client_data, CXDiagnosticSet set, void *reserved) {
    unsigned int num = clang_getNumDiagnosticsInSet(set);
    for (unsigned int i = 0; i < num; i++) {
        CXDiagnostic dia = clang_getDiagnosticInSet(set, i);
        NSLog(@"---4 %s", clang_getCString(clang_getDiagnosticSpelling(dia)));
    }
}


CXIdxClientFile enteredMainFile(CXClientData client_data,
                                CXFile mainFile, void *reserved) {
    NSLog(@"---7 %s", clang_getCString(clang_getFileName(mainFile)));
    return 0;
}

/**
 * Called when a file gets \#included/\#imported.
 */
CXIdxClientFile ppIncludedFile(CXClientData client_data,
                               const CXIdxIncludedFileInfo *fileInfo) {
    NSLog(@"---6 %s", fileInfo->filename);
    return 0;
}

/**
 * Called when a AST file (PCH or module) gets imported.
 *
 * AST files will not get indexed (there will not be callbacks to index all
 * the entities in an AST file). The recommended action is that, if the AST
 * file is not already indexed, to initiate a new indexing job specific to
 * the AST file.
 */
CXIdxClientASTFile importedASTFile(CXClientData client_data,
                                   const CXIdxImportedASTFileInfo *fileInfo) {
    NSLog(@"---5 %s", clang_getCString(clang_getFileName(fileInfo->file)));
    return 0;
}

/**
 * Called at the beginning of indexing a translation unit.
 */
CXIdxClientContainer startedTranslationUnit(CXClientData client_data,
                                            void *reserved) {
    
    return NULL;
}


void indexEntityReference(CXClientData client_data, const CXIdxEntityRefInfo *entityRefInfo) {
    NSLog(@"---2 %s", entityRefInfo->referencedEntity->name);
}

void indexDeclaration(CXClientData client_data, const CXIdxDeclInfo *declInfo) {
    NSLog(@"---3 %s", declInfo->entityInfo->name);
}


enum CXChildVisitResult _visitStrings(CXCursor cursor,
                                      CXCursor parent,
                                      CXClientData clientData) {
    if (clientData == NULL) return CXChildVisit_Break;
    
    MJStringsClientData *data = (__bridge MJStringsClientData *)clientData;
    if (!_isFromFile(data.file.UTF8String, cursor)) return CXChildVisit_Continue;
    
    if (cursor.kind == CXCursor_StringLiteral) {
        const char *name = _getCursorName(cursor);
        NSString *js = [NSString stringWithFormat:@"decodeURIComponent(escape(%s))", name];
        NSString *string = [[[JSContext alloc] init] evaluateScript:js].toString;
        [data.strings addObject:string];
    }

    return CXChildVisit_Recurse;
}

+ (NSSet *)stringsWithFile:(NSString *)file
                searchPath:(NSString *)searchPath
{
    MJStringsClientData *data = [[MJStringsClientData alloc] init];
    data.file = file;
    data.strings = [NSMutableSet set];
    [self _visitASTWithFile:file
                 searchPath:searchPath
                    visitor:_visitStrings
                 clientData:(__bridge void *)data];
    return data.strings;
}

+ (NSArray <NSSet *>*)classesAndMethodsWithFile:(NSString *)file
                            prefixes:(NSArray *)prefixes
                          searchPath:(NSString *)searchPath
{
    MJTokensClientData *data = [[MJTokensClientData alloc] init];
    data.file = file;
    data.prefixes = prefixes;
    data.tokens = [NSMutableSet set];
    data.categorys = [NSMutableSet set];
    data.tokensWhiteList = tokensWhiteList;
    data.categorysWhiteList = categorysWhiteList;
    [self _visitASTWithFile:file
                 searchPath:searchPath
                    visitor:_visitTokens
                 clientData:(__bridge void *)data];
    return @[data.tokens, data.categorys];
}

/** 遍历某个文件的语法树 */
+ (void)_visitASTWithFile:(NSString *)file
               searchPath:(NSString *)searchPath
                  visitor:(CXCursorVisitor)visitor
               clientData:(CXClientData)clientData
{
    if (file.length == 0) return;
    
    // 文件路径
    const char *filepath = file.UTF8String;
    
    // 创建index
    CXIndex index = clang_createIndex(1, 1);
    
    // 搜索路径
    int argCount = 5;
    NSArray *subDirs = nil;
    if (searchPath.length) {
        subDirs = [NSFileManager mj_subdirsAtPath:searchPath];
        argCount += ((int)subDirs.count + 1) * 2;
    }
    
    int argIndex = 0;
    const char **args = malloc(sizeof(char *) * argCount);
    args[argIndex++] = "-c";
    args[argIndex++] = "-arch";
    args[argIndex++] = "i386";
    args[argIndex++] = "-isysroot";
    args[argIndex++] = "/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneSimulator.platform/Developer/SDKs/iPhoneSimulator.sdk";
    // </Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Library/Developer/CoreSimulator/Profiles/Runtimes/iOS.simruntime/Contents/Resources/RuntimeRoot/System/Library/PrivateFrameworks/UIKitCore.framework>
    if (searchPath.length) {
        args[argIndex++] = "-I";
        args[argIndex++] = searchPath.UTF8String;
    }
    for (NSString *subDir in subDirs) {
        args[argIndex++] = "-I";
        args[argIndex++] = subDir.UTF8String;
    }
    
    // 解析语法树，返回根节点TranslationUnit
    CXTranslationUnit tu = clang_parseTranslationUnit(index, filepath,
                                                      args,
                                                      argCount,
                                                      NULL, 0, CXTranslationUnit_None);
    free(args);
    
    if (!tu) return;
    
    // 解析语法树
    clang_visitChildren(clang_getTranslationUnitCursor(tu),
                        visitor, clientData);
    
    CXIndexAction action = clang_IndexAction_create(index);
    IndexerCallbacks index_callbacks = {0};
//    index_callbacks.diagnostic = diagnostic;
    clang_indexTranslationUnit(action, clientData, &index_callbacks, sizeof(index_callbacks), CXIndexOpt_None, tu);
    
    // 销毁
    clang_IndexAction_dispose(action);
    clang_disposeTranslationUnit(tu);
    clang_disposeIndex(index);
}

@end
