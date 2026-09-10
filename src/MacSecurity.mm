#import "MacSecurity.hpp"
#import <AVFoundation/AVFoundation.h>
#import <ApplicationServices/ApplicationServices.h>
#import <Security/Security.h>
#import <OpenDirectory/OpenDirectory.h>
#import <sys/sysctl.h>
#import <unistd.h>
#include <cstring>
#include <vector>

namespace fg {
static NSString *const service = @"org.facegate.FaceGate";
static NSString *const modelID = @"sface-0ba9fbfa-128-v1";
double clockNow() { return CMTimeGetSeconds(CMClockGetTime(CMClockGetHostTimeClock())); }
NSString *osBuild() {
    char value[128] = {}; size_t size = sizeof(value);
    if (sysctlbyname("kern.osversion", value, &size, nullptr, 0) != 0) return @"unknown";
    return [NSString stringWithUTF8String:value] ?: @"unknown";
}
NSString *appBuild() {
    // Pin the actual code directory hash, not just the marketing version.
    SecCodeRef code = nullptr; SecStaticCodeRef staticCode = nullptr; CFDictionaryRef info = nullptr;
    NSString *hash = @"unknown";
    if (SecCodeCopySelf(kSecCSDefaultFlags, &code) == errSecSuccess &&
        SecCodeCopyStaticCode(code, kSecCSDefaultFlags, &staticCode) == errSecSuccess &&
        SecCodeCopySigningInformation(staticCode, kSecCSSigningInformation, &info) == errSecSuccess) {
        NSData *data = ((__bridge NSDictionary *)info)[(__bridge NSString *)kSecCodeInfoUnique];
        if (data.length) {
            NSMutableString *hex = [NSMutableString string];
            for (NSUInteger i = 0; i < data.length; ++i) [hex appendFormat:@"%02x", ((const unsigned char *)data.bytes)[i]];
            hash = hex;
        }
    }
    if (info) CFRelease(info);
    if (staticCode) CFRelease(staticCode);
    if (code) CFRelease(code);
    return hash;
}
Session session() {
    Session s;
    NSDictionary *d = CFBridgingRelease(CGSessionCopyCurrentDictionary());
    if (![d isKindOfClass:[NSDictionary class]]) return s;
    id uid = d[(__bridge NSString *)kCGSessionUserIDKey];
    id console = d[(__bridge NSString *)kCGSessionOnConsoleKey];
    id done = d[(__bridge NSString *)kCGSessionLoginDoneKey];
    if (![uid isKindOfClass:[NSNumber class]] || ![console isKindOfClass:[NSNumber class]] ||
        ![done isKindOfClass:[NSNumber class]]) return s;
    s.currentUser = [uid unsignedIntValue] == getuid();
    s.onConsole = [console boolValue]; s.loginComplete = [done boolValue];
    // This dictionary key is undocumented. Absence never authorizes a submission.
    id locked = d[@"CGSSessionScreenIsLocked"];
    s.known = [locked isKindOfClass:[NSNumber class]];
    s.locked = s.known && [locked boolValue];
    return s;
}
static void setError(OSStatus status, NSError **error) {
    if (!error) return;
    NSString *message = CFBridgingRelease(SecCopyErrorMessageString(status, nullptr));
    *error = [NSError errorWithDomain:NSOSStatusErrorDomain code:status
        userInfo:@{NSLocalizedDescriptionKey: message ?: @"Keychain operation failed"}];
}
static NSMutableDictionary *query(NSString *account) {
    return [@{(__bridge id)kSecClass:(__bridge id)kSecClassGenericPassword,
        (__bridge id)kSecAttrService:service, (__bridge id)kSecAttrAccount:account,
        (__bridge id)kSecAttrSynchronizable:@NO} mutableCopy];
}
NSData *keychainRead(NSString *account, bool interactive, NSError **error) {
    NSMutableDictionary *q = query(account);
    q[(__bridge id)kSecReturnData] = @YES;
    q[(__bridge id)kSecMatchLimit] = (__bridge id)kSecMatchLimitOne;
    if (!interactive) q[(__bridge id)kSecUseAuthenticationUI] = (__bridge id)kSecUseAuthenticationUIFail;
    CFTypeRef result = nullptr;
    OSStatus status = SecItemCopyMatching((__bridge CFDictionaryRef)q, &result);
    if (status != errSecSuccess) { setError(status, error); return nil; }
    id value = CFBridgingRelease(result);
    return [value isKindOfClass:[NSData class]] ? value : nil;
}
bool keychainWrite(NSString *account, NSData *value, NSError **error) {
    NSMutableDictionary *q = query(account);
    NSDictionary *change = @{(__bridge id)kSecValueData:value};
    OSStatus status = SecItemUpdate((__bridge CFDictionaryRef)q, (__bridge CFDictionaryRef)change);
    if (status == errSecItemNotFound) {
        q[(__bridge id)kSecValueData] = value;
        // Default macOS Keychain access binds the entry to this signed executable.
        status = SecItemAdd((__bridge CFDictionaryRef)q, nullptr);
    }
    if (status != errSecSuccess) setError(status, error);
    return status == errSecSuccess;
}
bool keychainDelete(NSString *account, NSError **error) {
    OSStatus status = SecItemDelete((__bridge CFDictionaryRef)query(account));
    if (status == errSecItemNotFound) return true;
    if (status != errSecSuccess) setError(status, error);
    return status == errSecSuccess;
}
bool verifyPassword(NSString *password, NSError **error) {
    ODNode *node = [ODNode nodeWithSession:[ODSession defaultSession] type:kODNodeTypeLocalNodes error:error];
    ODRecord *record = [node recordWithRecordType:kODRecordTypeUsers name:NSUserName() attributes:nil error:error];
    return record && [record verifyPassword:password error:error];
}
bool saveOwner(const Embedding &owner, NSError **error) {
    NSMutableArray *values = [NSMutableArray arrayWithCapacity:embeddingSize];
    for (float x : owner) [values addObject:@(x)];
    NSData *data = [NSJSONSerialization dataWithJSONObject:@{@"model":modelID, @"embedding":values}
        options:0 error:error];
    return data && keychainWrite(@"owner-template", data, error);
}
bool loadOwner(Embedding &owner, NSError **error) {
    NSData *data = keychainRead(@"owner-template", false, error);
    if (!data || data.length > 16384) return false;
    id doc = [NSJSONSerialization JSONObjectWithData:data options:0 error:error];
    if (![doc isKindOfClass:[NSDictionary class]] || ![doc[@"model"] isEqual:modelID]) return false;
    id values = doc[@"embedding"];
    if (![values isKindOfClass:[NSArray class]] || [values count] != embeddingSize) return false;
    for (size_t i = 0; i < embeddingSize; ++i) {
        if (![values[i] isKindOfClass:[NSNumber class]]) return false;
        owner[i] = [values[i] floatValue];
    }
    return normalize(owner);
}
static id axValue(AXUIElementRef element, CFStringRef key) {
    CFTypeRef value = nullptr;
    if (AXUIElementCopyAttributeValue(element, key, &value) != kAXErrorSuccess) return nil;
    return CFBridgingRelease(value);
}
static bool userLabel(AXUIElementRef element, int depth, int &budget) {
    if (!element || depth > 6 || --budget < 0) return false;
    id role = axValue(element, kAXRoleAttribute);
    if ([role isEqual:(__bridge NSString *)kAXStaticTextRole]) {
        for (NSString *key in @[(__bridge NSString *)kAXValueAttribute, (__bridge NSString *)kAXTitleAttribute]) {
            id text = axValue(element, (__bridge CFStringRef)key);
            if ([text isKindOfClass:[NSString class]] &&
                ([text isEqualToString:NSUserName()] || [text isEqualToString:NSFullUserName()])) return true;
        }
    }
    id children = axValue(element, kAXChildrenAttribute);
    if ([children isKindOfClass:[NSArray class]]) {
        for (id child in children) {
            if (CFGetTypeID((__bridge CFTypeRef)child) == AXUIElementGetTypeID() &&
                userLabel((__bridge AXUIElementRef)child, depth + 1, budget)) return true;
            if (budget < 0) break;
        }
    }
    return false;
}
static bool appleTarget(NSRunningApplication *app) {
    if (!app || app.terminated) return false;
    bool knownID = [app.bundleIdentifier isEqualToString:@"com.apple.loginwindow"] ||
                   [app.bundleIdentifier isEqualToString:@"com.apple.SecurityAgent"];
    if (!knownID || ![app.bundleURL.path hasPrefix:@"/System/Library/CoreServices/"]) return false;
    SecCodeRef code = nullptr; SecRequirementRef requirement = nullptr;
    NSDictionary *guest = @{(__bridge id)kSecGuestAttributePid:@(app.processIdentifier)};
    OSStatus status = SecCodeCopyGuestWithAttributes(nullptr, (__bridge CFDictionaryRef)guest,
        kSecCSDefaultFlags, &code);
    if (status == errSecSuccess) status = SecRequirementCreateWithString(CFSTR("anchor apple"),
        kSecCSDefaultFlags, &requirement);
    if (status == errSecSuccess) status = SecCodeCheckValidity(code, kSecCSDefaultFlags, requirement);
    if (requirement) CFRelease(requirement);
    if (code) CFRelease(code);
    return status == errSecSuccess;
}
static bool sameLock(pid_t pid) {
    Session s = session();
    NSRunningApplication *app = NSWorkspace.sharedWorkspace.frontmostApplication;
    return s.known && s.locked && s.currentUser && s.onConsole && s.loginComplete &&
        app.processIdentifier == pid && appleTarget(app);
}
static bool emptySecureField(AXUIElementRef field) {
    if (![axValue(field, kAXSubroleAttribute) isEqual:(__bridge NSString *)kAXSecureTextFieldSubrole]) return false;
    id count = axValue(field, kAXNumberOfCharactersAttribute);
    id value = axValue(field, kAXValueAttribute);
    bool hasCount = [count isKindOfClass:[NSNumber class]];
    bool hasValue = [value isKindOfClass:[NSString class]];
    // Contradictory accessibility values fail closed.
    if ((hasCount && [count integerValue] != 0) || (hasValue && [value length] != 0)) return false;
    return hasCount || hasValue;
}
NSString *submitCredential(double matchedAt, bool alreadyAttempted) {
    NSUserDefaults *prefs = NSUserDefaults.standardUserDefaults;
    UnlockEvidence e;
    e.optedIn = [prefs boolForKey:@"experimentalUnlock"];
    e.sameOSBuild = ![osBuild() isEqual:@"unknown"] && [osBuild() isEqual:[prefs stringForKey:@"allowedOSBuild"]];
    e.sameAppBuild = ![appBuild() isEqual:@"unknown"] && [appBuild() isEqual:[prefs stringForKey:@"allowedAppBuild"]];
    Session s = session();
    e.locked = s.known && s.locked; e.currentUser = s.currentUser;
    e.onConsole = s.onConsole; e.loginComplete = s.loginComplete;
    e.accessibility = AXIsProcessTrusted(); e.alreadyAttempted = alreadyAttempted;
    e.matchAge = clockNow() - matchedAt;
    if (!e.optedIn || !e.sameOSBuild || !e.sameAppBuild) return @"Recognition succeeded. Unlock is disabled on this app/OS build.";
    if (!e.locked || !e.currentUser || !e.onConsole || !e.loginComplete || !e.accessibility)
        return @"Lock session or Accessibility could not be verified. Use your password.";
    NSRunningApplication *app = NSWorkspace.sharedWorkspace.frontmostApplication;
    e.trustedTarget = appleTarget(app);
    if (!e.trustedTarget) return @"macOS does not expose a supported lock-screen process. Use your password.";
    AXUIElementRef target = AXUIElementCreateApplication(app.processIdentifier);
    AXUIElementSetMessagingTimeout(target, 0.10);
    id focus = axValue(target, kAXFocusedUIElementAttribute);
    if (focus && CFGetTypeID((__bridge CFTypeRef)focus) == AXUIElementGetTypeID()) {
        AXUIElementRef field = (__bridge AXUIElementRef)focus;
        e.secureField = [axValue(field, kAXSubroleAttribute) isEqual:(__bridge NSString *)kAXSecureTextFieldSubrole];
        e.emptyField = emptySecureField(field);
        id window = axValue(field, kAXWindowAttribute);
        int budget = 120;
        if (window && CFGetTypeID((__bridge CFTypeRef)window) == AXUIElementGetTypeID())
            e.userLabel = userLabel((__bridge AXUIElementRef)window, 0, budget);
    }
    CFRelease(target);
    e.matchAge = clockNow() - matchedAt;
    if (!canSubmit(e)) return @"Could not verify an empty password field for this user. Use your password.";
    NSError *error = nil;
    NSData *data = keychainRead(@"login-password", false, &error);
    if (!data) return @"Saved password is unavailable while locked. Use your password.";
    NSString *password = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    if (password.length == 0 || password.length > 128) return @"Saved password is invalid. Reconfigure FaceGate.";
    // Recheck after Keychain access and immediately before PID-targeted input.
    if (!sameLock(app.processIdentifier) || clockNow() - matchedAt > 0.35)
        return @"Lock-screen state changed. Use your password.";
    AXUIElementRef freshTarget = AXUIElementCreateApplication(app.processIdentifier);
    AXUIElementSetMessagingTimeout(freshTarget, 0.10);
    id freshFocus = axValue(freshTarget, kAXFocusedUIElementAttribute);
    bool unchanged = freshFocus && CFGetTypeID((__bridge CFTypeRef)freshFocus) == AXUIElementGetTypeID() &&
        CFEqual((__bridge CFTypeRef)freshFocus, (__bridge CFTypeRef)focus) &&
        emptySecureField((__bridge AXUIElementRef)freshFocus);
    CFRelease(freshTarget);
    if (!unchanged || clockNow() - matchedAt > 0.35) return @"Password field changed. Use your password.";
    std::vector<UniChar> characters(password.length);
    [password getCharacters:characters.data() range:NSMakeRange(0, password.length)];
    CGEventSourceRef source = CGEventSourceCreate(kCGEventSourceStatePrivate);
    CGEventRef down = CGEventCreateKeyboardEvent(source, 0, true);
    CGEventRef up = CGEventCreateKeyboardEvent(source, 0, false);
    if (!source || !down || !up) {
        if (down) CFRelease(down); if (up) CFRelease(up); if (source) CFRelease(source);
        explicit_bzero(characters.data(), characters.size() * sizeof(UniChar));
        return @"Input event could not be created. Use your password.";
    }
    CGEventSetFlags(down, 0); CGEventSetFlags(up, 0);
    CGEventKeyboardSetUnicodeString(down, characters.size(), characters.data());
    CGEventKeyboardSetUnicodeString(up, characters.size(), characters.data());
    // Never use global CGEventPost, clipboard, AppleScript, or shell interpolation.
    CGEventPostToPid(app.processIdentifier, down); CGEventPostToPid(app.processIdentifier, up);
    CFRelease(down); CFRelease(up);
    explicit_bzero(characters.data(), characters.size() * sizeof(UniChar));
    if (sameLock(app.processIdentifier)) {
        CGEventRef enterDown = CGEventCreateKeyboardEvent(source, 36, true);
        CGEventRef enterUp = CGEventCreateKeyboardEvent(source, 36, false);
        if (enterDown && enterUp) {
            CGEventSetFlags(enterDown, 0); CGEventSetFlags(enterUp, 0);
            CGEventPostToPid(app.processIdentifier, enterDown);
            CGEventPostToPid(app.processIdentifier, enterUp);
        }
        if (enterDown) CFRelease(enterDown); if (enterUp) CFRelease(enterUp);
    }
    CFRelease(source);
    return @"One credential submission attempted. macOS decides whether to accept it.";
}
NSDictionary *diagnostics() {
    Session s = session();
    return @{@"app":@"FaceGate", @"version":@"0.1.0", @"os_build":osBuild(),
        @"code_hash":appBuild(), @"architecture":@"x86_64 target",
        @"lock_state_known":@(s.known), @"locked":@(s.locked),
        @"current_user":@(s.currentUser), @"on_console":@(s.onConsole),
        @"login_complete":@(s.loginComplete), @"accessibility":@(AXIsProcessTrusted()),
        @"camera_authorized":@([AVCaptureDevice authorizationStatusForMediaType:AVMediaTypeVideo] == AVAuthorizationStatusAuthorized),
        @"unlock_backend":@"experimental; requires live hardware validation"};
}
}
