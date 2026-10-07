#!/usr/bin/env python3
"""Compile the real generated Objective-C lowercase helper and argument formatter."""
from pathlib import Path
import subprocess


def run(source: Path, package: Path):
    package.mkdir(parents=True, exist_ok=True)
    strings = package / "fixture.strings"
    strings.write_text('"Label" = "HELLO";\n"Formatted" = "HELLO %@";\n', encoding="utf-8")
    header = package / "PresentationStrings/PresentationStrings.h"
    header.parent.mkdir(parents=True, exist_ok=True)
    implementation = package / "PresentationStrings.m"
    subprocess.run(["python3", str(source / "build-system/GenerateStrings/GenerateStrings.py"),
                    "--source", str(strings), "--outHeader", str(header),
                    "--outImplementation", str(implementation), "--outData", str(package / "strings.data")], check=True)
    code = implementation.read_text(encoding="utf-8")
    classes = code[code.index("@implementation _FormattedStringRange"):code.index("@implementation _PresentationStringsComponent")]
    formatter = code[code.index("static NSArray<_FormattedStringRange *>"):code.index("static NSString * _Nonnull getPluralizationSuffix")]
    lowercase = code[code.index("static NSString * _Nonnull faithgramInterfaceTemplate"):code.index("static NSString * _Nonnull getSingle(")]
    driver = r'''
int main(void) {
    @autoreleasepool {
        NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
        NSString *key = @"patchclient.option.lowercaseInterface";
        [defaults setBool:NO forKey:key];
        NSCAssert([faithgramInterfaceTemplate(@"HELLO %@") isEqualToString:@"HELLO %@"], @"Disabled mode changed a template");
        [defaults setBool:YES forKey:key];
        NSString *template = faithgramInterfaceTemplate(@"HELLO %1$@ IN %2$@ HTTP://Example.COM/Path?Q=X");
        NSCAssert([template isEqualToString:@"hello %1$@ in %2$@ HTTP://Example.COM/Path?Q=X"], @"UI lowercase changed a URL or placeholder");
        NSArray *arguments = @[@"ALiCe 🧹", @"HTTPS://Example.COM/MixedCASE"];
        _FormattedString *value = formatWithArgumentRanges(template, extractArgumentRanges(template), arguments);
        NSCAssert([value.string containsString:arguments[0]] && [value.string containsString:arguments[1]], @"User content changed case");
        for (_FormattedStringRange *range in value.ranges) {
            NSCAssert([[value.string substringWithRange:range.range] isEqualToString:arguments[range.index]], @"Formatting ranges no longer identify the argument");
        }
        NSString *unicode = faithgramInterfaceTemplate(@"İ %@ STRASSE");
        _FormattedString *expanded = formatWithArgumentRanges(unicode, extractArgumentRanges(unicode), @[@"User 🧹"]);
        NSCAssert([[expanded.string substringWithRange:expanded.ranges[0].range] isEqualToString:@"User 🧹"], @"Unicode lowercase broke UTF-16 argument ranges");
        [defaults removeObjectForKey:key];
    }
    return 0;
}
'''
    test = package / "interface-tests.m"
    test.write_text('#import <Foundation/Foundation.h>\n#import <dispatch/dispatch.h>\n#import "PresentationStrings/PresentationStrings.h"\n' + classes + formatter + lowercase + driver, encoding="utf-8")
    binary = package / "interface-tests"
    subprocess.run(["xcrun", "clang", "-fobjc-arc", "-fmodules", "-framework", "Foundation", "-I", str(package), str(test), "-o", str(binary)], check=True)
    subprocess.run([str(binary)], check=True)
    print("PASS: generated Objective-C UI lowercase preserves names, URLs, placeholders and Unicode argument ranges.")
