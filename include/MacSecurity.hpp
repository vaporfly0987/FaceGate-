#pragma once
#import <Cocoa/Cocoa.h>
#include "Gate.hpp"

namespace fg {
double clockNow();
NSString *osBuild();
NSString *appBuild();
struct Session {
    bool known = false, locked = false, currentUser = false;
    bool onConsole = false, loginComplete = false;
};
Session session();
NSData *keychainRead(NSString *account, bool interactive, NSError **error);
bool keychainWrite(NSString *account, NSData *value, NSError **error);
bool keychainDelete(NSString *account, NSError **error);
bool verifyPassword(NSString *password, NSError **error);
bool saveOwner(const Embedding &owner, NSError **error);
bool loadOwner(Embedding &owner, NSError **error);
NSDictionary *diagnostics();
NSString *submitCredential(double matchedAt, bool alreadyAttempted);
}
