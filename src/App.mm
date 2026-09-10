#import <Cocoa/Cocoa.h>
#import <AVFoundation/AVFoundation.h>
#import <LocalAuthentication/LocalAuthentication.h>
#import <ApplicationServices/ApplicationServices.h>
#import "MacSecurity.hpp"
#include "Recognizer.hpp"
#include <opencv2/imgproc.hpp>
#include <atomic>
#include <cstring>
#include <memory>
#include <vector>
#include <unistd.h>

@interface FGApp : NSObject <NSApplicationDelegate, AVCaptureVideoDataOutputSampleBufferDelegate, NSWindowDelegate> {
    NSStatusItem *_status;
    NSWindow *_window;
    NSTextField *_message;
    NSView *_preview;
    NSButton *_unlock;
    NSButton *_warm;
    AVCaptureVideoPreviewLayer *_previewLayer;
    AVCaptureSession *_camera;
    AVSpeechSynthesizer *_speech;
    dispatch_queue_t _work;
    std::unique_ptr<fg::Recognizer> _recognizer;
    std::atomic<bool> _frames;
    std::atomic<bool> _busy;
    std::atomic<unsigned> _epoch;
    double _lastFrame;
    fg::Embedding _owner;
    bool _hasOwner;
    fg::Gate _gate;
    std::vector<fg::Embedding> _samples;
    NSTimer *_timer;
    bool _enrolling, _testing, _paused, _sleeping, _locked, _attempted;
    bool _cameraRequested, _cameraReady, _modelsReady, _starting;
    double _startedAt, _sampleAt, _retryAt;
    double _lastAcceptedFrame;
    int _desktopTicks;
}
- (void)process:(fg::FaceResult)result;
- (void)authorize:(NSString *)reason then:(void (^)(void))completion;
@end

static NSButton *button(NSString *title, id target, SEL action, NSRect frame) {
    NSButton *b = [NSButton buttonWithTitle:title target:target action:action];
    b.frame = frame;
    return b;
}
static void alert(NSString *title, NSString *detail) {
    NSAlert *a = [NSAlert new]; a.messageText = title; a.informativeText = detail;
    [a addButtonWithTitle:@"OK"]; [a runModal];
}

@implementation FGApp
- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    (void)notification;
    if (getuid() == 0) { fprintf(stderr, "Run FaceGate as your logged-in user, never with sudo.\n"); exit(1); }
    NSArray *others = [NSRunningApplication runningApplicationsWithBundleIdentifier:@"org.facegate.FaceGate"];
    for (NSRunningApplication *app in others) {
        if (app.processIdentifier != getpid()) { [app activateWithOptions:NSApplicationActivateIgnoringOtherApps]; [NSApp terminate:nil]; return; }
    }
    _work = dispatch_queue_create("org.facegate.camera", DISPATCH_QUEUE_SERIAL);
    _speech = [AVSpeechSynthesizer new];
    _frames = false; _busy = false; _epoch = 0;
    _attempted = [NSUserDefaults.standardUserDefaults boolForKey:@"attemptPending"];
    _hasOwner = fg::loadOwner(_owner, nullptr);
    _status = [NSStatusBar.systemStatusBar statusItemWithLength:NSVariableStatusItemLength];
    _status.button.title = @"FG";
    NSMenu *menu = [NSMenu new];
    for (NSArray *entry in @[@[@"Open FaceGate…", NSStringFromSelector(@selector(show:))],
                            @[@"Pause / resume recognition", NSStringFromSelector(@selector(pause:))],
                            @[@"Quit until next login", NSStringFromSelector(@selector(stop:))]]) {
        NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:entry[0] action:NSSelectorFromString(entry[1]) keyEquivalent:@""];
        item.target = self; [menu addItem:item];
    }
    _status.menu = menu;
    [self createWindow];
    NSString *models = NSBundle.mainBundle.resourcePath;
    dispatch_async(_work, ^{
        try {
            self->_recognizer = std::make_unique<fg::Recognizer>(models.fileSystemRepresentation);
            dispatch_async(dispatch_get_main_queue(), ^{ self->_modelsReady = true; [self tick:nil]; });
        } catch (const std::exception &e) {
            NSString *detail = [NSString stringWithUTF8String:e.what()];
            dispatch_async(dispatch_get_main_queue(), ^{ [self setMessage:[@"Model loading failed: " stringByAppendingString:detail]]; });
        }
    });
    NSNotificationCenter *nc = NSWorkspace.sharedWorkspace.notificationCenter;
    [nc addObserver:self selector:@selector(sleep:) name:NSWorkspaceWillSleepNotification object:nil];
    [nc addObserver:self selector:@selector(wake:) name:NSWorkspaceDidWakeNotification object:nil];
    [nc addObserver:self selector:@selector(sleep:) name:NSWorkspaceScreensDidSleepNotification object:nil];
    [nc addObserver:self selector:@selector(wake:) name:NSWorkspaceScreensDidWakeNotification object:nil];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(cameraError:)
        name:AVCaptureSessionRuntimeErrorNotification object:nil];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(cameraError:)
        name:AVCaptureSessionWasInterruptedNotification object:nil];
    _timer = [NSTimer scheduledTimerWithTimeInterval:0.5 target:self selector:@selector(tick:) userInfo:nil repeats:YES];
    [NSRunLoop.mainRunLoop addTimer:_timer forMode:NSRunLoopCommonModes];
    if (!_hasOwner || ![NSProcessInfo.processInfo.arguments containsObject:@"--background"]) [self show:nil];
    [self setMessage:_hasOwner ? @"Ready. Recognition runs when the screen is locked or during a test." : @"Enroll your face to begin. Processing stays on this Mac."];
}
- (BOOL)applicationShouldHandleReopen:(NSApplication *)app hasVisibleWindows:(BOOL)visible {
    (void)app; (void)visible; [self show:nil]; return YES;
}
- (void)createWindow {
    _window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 700, 620)
        styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable
        backing:NSBackingStoreBuffered defer:NO];
    _window.title = @"FaceGate · Intel macOS"; _window.delegate = self;
    _window.releasedWhenClosed = NO; [_window center];
    NSView *v = _window.contentView;
    NSTextField *title = [NSTextField labelWithString:@"Recognize your face. Keep control of your Mac."];
    title.font = [NSFont boldSystemFontOfSize:21]; title.frame = NSMakeRect(24, 570, 650, 28); [v addSubview:title];
    _preview = [[NSView alloc] initWithFrame:NSMakeRect(24, 230, 450, 320)];
    _preview.wantsLayer = YES; _preview.layer.backgroundColor = NSColor.blackColor.CGColor;
    [v addSubview:_preview];
    [v addSubview:button(@"1. Enable camera", self, @selector(cameraPermission:), NSMakeRect(490, 506, 186, 34))];
    [v addSubview:button(@"2. Enroll my face", self, @selector(enroll:), NSMakeRect(490, 460, 186, 34))];
    [v addSubview:button(@"3. Test recognition", self, @selector(test:), NSMakeRect(490, 414, 186, 34))];
    [v addSubview:button(@"Cancel / stop preview", self, @selector(cancel:), NSMakeRect(490, 368, 186, 34))];
    [v addSubview:button(@"Delete saved data", self, @selector(deleteData:), NSMakeRect(490, 278, 186, 34))];
    _message = [NSTextField wrappingLabelWithString:@"Starting…"];
    _message.frame = NSMakeRect(24, 163, 652, 54); _message.font = [NSFont systemFontOfSize:14]; [v addSubview:_message];
    _warm = [NSButton checkboxWithTitle:@"Keep camera warm while awake for a faster start (camera light stays on)"
        target:self action:@selector(warm:)];
    _warm.frame = NSMakeRect(24, 128, 652, 24);
    _warm.state = [NSUserDefaults.standardUserDefaults boolForKey:@"warmCamera"] ? NSControlStateValueOn : NSControlStateValueOff;
    [v addSubview:_warm];
    _unlock = [NSButton checkboxWithTitle:@"Experimental: submit my saved Mac password after recognition"
        target:self action:@selector(unlockChanged:)];
    _unlock.frame = NSMakeRect(24, 96, 652, 24);
    _unlock.state = [NSUserDefaults.standardUserDefaults boolForKey:@"experimentalUnlock"] ? NSControlStateValueOn : NSControlStateValueOff;
    [v addSubview:_unlock];
    NSTextField *note = [NSTextField wrappingLabelWithString:@"Webcam recognition is vulnerable to spoofing. Lock-screen submission may be blocked by macOS; developer betas require testing. After restarting, sign in normally first."];
    note.frame = NSMakeRect(24, 20, 652, 62); note.textColor = NSColor.secondaryLabelColor; [v addSubview:note];
}
- (void)setMessage:(NSString *)message { _message.stringValue = message; _status.button.toolTip = message; }
- (void)show:(id)sender { (void)sender; [NSApp activateIgnoringOtherApps:YES]; [_window makeKeyAndOrderFront:nil]; }
- (void)windowWillClose:(NSNotification *)n { (void)n; [self cancel:nil]; }
- (void)authorize:(NSString *)reason then:(void (^)(void))completion {
    if (fg::session().locked) { [self setMessage:@"Unlock your Mac before changing setup."]; return; }
    LAContext *context = [LAContext new];
    [context evaluatePolicy:LAPolicyDeviceOwnerAuthentication localizedReason:reason reply:^(BOOL success, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (success && !fg::session().locked) completion();
            else [self setMessage:error.localizedDescription ?: @"Authentication was cancelled."];
        });
    }];
}
- (void)cameraPermission:(id)sender {
    (void)sender;
    [AVCaptureDevice requestAccessForMediaType:AVMediaTypeVideo completionHandler:^(BOOL granted) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (granted) { self->_cameraRequested = true; [self tick:nil]; }
            else [self setMessage:@"Allow FaceGate in System Settings → Privacy & Security → Camera."];
        });
    }];
}
- (void)ensureCamera {
    if (_starting || _cameraReady) return;
    if ([AVCaptureDevice authorizationStatusForMediaType:AVMediaTypeVideo] != AVAuthorizationStatusAuthorized) return;
    _starting = true;
    dispatch_async(_work, ^{
        @autoreleasepool {
            if (!self->_camera) {
                self->_camera = [AVCaptureSession new];
                [self->_camera beginConfiguration];
                if ([self->_camera canSetSessionPreset:AVCaptureSessionPreset640x480]) self->_camera.sessionPreset = AVCaptureSessionPreset640x480;
                AVCaptureDeviceDiscoverySession *devices = [AVCaptureDeviceDiscoverySession
                    discoverySessionWithDeviceTypes:@[AVCaptureDeviceTypeBuiltInWideAngleCamera]
                    mediaType:AVMediaTypeVideo position:AVCaptureDevicePositionUnspecified];
                AVCaptureDevice *device = devices.devices.firstObject;
                // Deliberately avoid selecting a software virtual camera as an automatic fallback.
                NSError *error = nil;
                AVCaptureDeviceInput *input = device ? [AVCaptureDeviceInput deviceInputWithDevice:device error:&error] : nil;
                AVCaptureVideoDataOutput *output = [AVCaptureVideoDataOutput new];
                output.videoSettings = @{(id)kCVPixelBufferPixelFormatTypeKey:@(kCVPixelFormatType_32BGRA)};
                output.alwaysDiscardsLateVideoFrames = YES;
                [output setSampleBufferDelegate:self queue:self->_work];
                if (!input || ![self->_camera canAddInput:input] || ![self->_camera canAddOutput:output]) {
                    [self->_camera commitConfiguration]; self->_camera = nil;
                    dispatch_async(dispatch_get_main_queue(), ^{
                        self->_starting = false; self->_retryAt = fg::clockNow() + 10;
                        [self setMessage:error.localizedDescription ?: @"Built-in camera unavailable. Check camera permission and other apps."];
                    }); return;
                }
                [self->_camera addInput:input]; [self->_camera addOutput:output];
                [self->_camera commitConfiguration];
            }
            [self->_camera startRunning];
            BOOL running = self->_camera.running;
            dispatch_async(dispatch_get_main_queue(), ^{
                self->_starting = false; self->_cameraReady = running;
                self->_lastAcceptedFrame = fg::clockNow();
                if (!running) { self->_retryAt = fg::clockNow() + 10; [self setMessage:@"Camera could not start. Use your Mac password."]; }
                if (running && !self->_previewLayer) {
                    self->_previewLayer = [AVCaptureVideoPreviewLayer layerWithSession:self->_camera];
                    self->_previewLayer.frame = self->_preview.bounds;
                    self->_previewLayer.videoGravity = AVLayerVideoGravityResizeAspectFill;
                    [self->_preview.layer addSublayer:self->_previewLayer];
                }
            });
        }
    });
}
- (void)stopCamera {
    _frames = false;
    if (!_cameraReady || _starting) return;
    _starting = true; _cameraReady = false;
    dispatch_async(_work, ^{
        [self->_camera stopRunning];
        dispatch_async(dispatch_get_main_queue(), ^{ self->_starting = false; });
    });
}
- (void)resetChallenge {
    _epoch.fetch_add(1); _gate.reset(fg::clockNow(), arc4random_uniform(2) ? 1 : -1);
    _startedAt = fg::clockNow();
    [_speech stopSpeakingAtBoundary:AVSpeechBoundaryImmediate];
    [self setMessage:@"Look straight at the camera."];
}
- (void)enroll:(id)sender {
    (void)sender;
    [self authorize:@"Enroll your face for local recognition" then:^{
        [self cancel:nil];
        self->_enrolling = true; self->_samples.clear(); self->_sampleAt = 0;
        self->_startedAt = fg::clockNow(); self->_cameraRequested = true;
        [self setMessage:@"Look toward the camera. Hold still, then vary your angle slightly. Collecting 8 samples."];
        [self tick:nil];
    }];
}
- (void)test:(id)sender {
    (void)sender;
    if (!_hasOwner) { [self setMessage:@"Enroll your face first."]; return; }
    [self cancel:nil]; _testing = true; _cameraRequested = true; [self resetChallenge]; [self tick:nil];
}
- (void)cancel:(id)sender {
    (void)sender;
    _enrolling = false; _testing = false; _cameraRequested = false;
    _samples.clear(); _epoch.fetch_add(1); _frames = false;
    _gate.reset(fg::clockNow(), arc4random_uniform(2) ? 1 : -1);
    [_speech stopSpeakingAtBoundary:AVSpeechBoundaryImmediate];
    [self setMessage:@"Ready. You can close this window; FaceGate stays in the menu bar."];
    [self tick:nil];
}
- (void)warm:(id)sender {
    (void)sender; [NSUserDefaults.standardUserDefaults setBool:_warm.state == NSControlStateValueOn forKey:@"warmCamera"];
    [self tick:nil];
}
- (void)pause:(id)sender {
    (void)sender; _paused = !_paused; [self cancel:nil];
    [self setMessage:_paused ? @"Recognition paused." : @"Recognition resumed."]; [self tick:nil];
}
- (void)sleep:(NSNotification *)n {
    (void)n; dispatch_async(dispatch_get_main_queue(), ^{
        self->_sleeping = true; self->_epoch.fetch_add(1); self->_enrolling = false;
        self->_testing = false; self->_cameraRequested = false; self->_samples.clear();
        [self->_speech stopSpeakingAtBoundary:AVSpeechBoundaryImmediate]; [self stopCamera];
    });
}
- (void)wake:(NSNotification *)n {
    (void)n; dispatch_async(dispatch_get_main_queue(), ^{
        self->_sleeping = false; self->_retryAt = 0; [self resetChallenge]; [self tick:nil];
    });
}
- (void)cameraError:(NSNotification *)n {
    (void)n; dispatch_async(dispatch_get_main_queue(), ^{
        self->_epoch.fetch_add(1); self->_retryAt = fg::clockNow() + 10;
        [self stopCamera]; [self setMessage:@"Camera interrupted. Recognition stopped; retrying in 10 seconds."];
    });
}
- (void)say:(NSString *)text {
    [_speech stopSpeakingAtBoundary:AVSpeechBoundaryImmediate];
    AVSpeechUtterance *u = [AVSpeechUtterance speechUtteranceWithString:text];
    u.rate = AVSpeechUtteranceDefaultSpeechRate; [_speech speakUtterance:u];
    [self setMessage:text];
}
- (void)tick:(NSTimer *)timer {
    (void)timer;
    fg::Session s = fg::session();
    bool lockedNow = s.known && s.locked;
    if (lockedNow != _locked) {
        _locked = lockedNow; _epoch.fetch_add(1);
        _enrolling = false; _testing = false; _samples.clear(); _cameraRequested = false;
        if (_locked) [self resetChallenge];
        else [_speech stopSpeakingAtBoundary:AVSpeechBoundaryImmediate];
    }
    // Only a running desktop app in this user's active session resets the attempt budget.
    NSRunningApplication *front = NSWorkspace.sharedWorkspace.frontmostApplication;
    bool desktop = !_locked && s.currentUser && s.onConsole && s.loginComplete &&
        front && ![front.bundleIdentifier isEqual:@"com.apple.loginwindow"] &&
        ![front.bundleIdentifier isEqual:@"com.apple.SecurityAgent"];
    _desktopTicks = desktop ? _desktopTicks + 1 : 0;
    if (_desktopTicks >= 3 && _attempted) {
        _attempted = false; [NSUserDefaults.standardUserDefaults setBool:NO forKey:@"attemptPending"];
    }
    NSUserDefaults *prefs = NSUserDefaults.standardUserDefaults;
    if ([prefs boolForKey:@"experimentalUnlock"] &&
        (![[prefs stringForKey:@"allowedOSBuild"] isEqual:fg::osBuild()] ||
         ![[prefs stringForKey:@"allowedAppBuild"] isEqual:fg::appBuild()])) {
        [prefs setBool:NO forKey:@"experimentalUnlock"]; _unlock.state = NSControlStateValueOff;
        [self setMessage:@"App or OS changed. Test recognition, then re-enable experimental unlock if desired."];
    }
    double now = fg::clockNow();
    if (_enrolling && now - _startedAt > 35) { [self cancel:nil]; [self setMessage:@"Enrollment timed out. Improve lighting and try again."]; }
    if ((_testing || (_locked && !_attempted)) && now - _startedAt > 12) {
        if (_testing) { [self cancel:nil]; [self setMessage:@"Recognition timed out. Try again with better lighting."]; }
        else [self resetChallenge];
    }
    bool active = _modelsReady && !_paused && !_sleeping && s.currentUser && s.onConsole && s.loginComplete && now >= _retryAt;
    bool recognize = active && (_enrolling || _testing || (_locked && _hasOwner && !_attempted));
    bool needCamera = active && (recognize || _cameraRequested || [prefs boolForKey:@"warmCamera"]);
    _frames = recognize;
    if (needCamera) [self ensureCamera]; else [self stopCamera];
    if (recognize && _cameraReady && now - _lastAcceptedFrame > 4) {
        _epoch.fetch_add(1); _retryAt = now + 10; [self stopCamera];
        [self setMessage:@"Camera frames stopped. Use your password; FaceGate will retry."];
    }
    _previewLayer.hidden = !_cameraRequested || _locked || _sleeping;
}
- (void)captureOutput:(AVCaptureOutput *)output didOutputSampleBuffer:(CMSampleBufferRef)sample fromConnection:(AVCaptureConnection *)connection {
    (void)output; (void)connection;
    if (!_frames.load() || !_recognizer || _busy.load()) return;
    double now = fg::clockNow();
    if (now - _lastFrame < 0.10) return; // At most 10 recognition frames per second.
    _lastFrame = now;
    CMClockRef clock = _camera.masterClock;
    if (!clock) return;
    CMTime converted = CMSyncConvertTime(CMSampleBufferGetPresentationTimeStamp(sample), clock, CMClockGetHostTimeClock());
    double captured = CMTimeGetSeconds(converted);
    if (!std::isfinite(captured) || now - captured > 0.35 || captured > now) return;
    if (_busy.exchange(true)) return;
    unsigned epoch = _epoch.load();
    @autoreleasepool {
        CVPixelBufferRef pixel = CMSampleBufferGetImageBuffer(sample);
        if (!pixel) { _busy = false; return; }
        CVPixelBufferLockBaseAddress(pixel, kCVPixelBufferLock_ReadOnly);
        cv::Mat bgra((int)CVPixelBufferGetHeight(pixel), (int)CVPixelBufferGetWidth(pixel),
            CV_8UC4, CVPixelBufferGetBaseAddress(pixel), CVPixelBufferGetBytesPerRow(pixel));
        cv::Mat bgr;
        try {
            cv::cvtColor(bgra, bgr, cv::COLOR_BGRA2BGR);
        } catch (...) {
            CVPixelBufferUnlockBaseAddress(pixel, kCVPixelBufferLock_ReadOnly); _busy = false; return;
        }
        CVPixelBufferUnlockBaseAddress(pixel, kCVPixelBufferLock_ReadOnly);
        try {
            fg::FaceResult result = _recognizer->analyze(bgr, captured, nullptr);
            dispatch_async(dispatch_get_main_queue(), ^{
                if (epoch == self->_epoch.load() && self->_frames.load()) [self process:result];
                self->_busy = false;
            });
        } catch (...) {
            dispatch_async(dispatch_get_main_queue(), ^{
                self->_busy = false; self->_epoch.fetch_add(1); self->_retryAt = fg::clockNow() + 10;
                [self stopCamera]; [self setMessage:@"Recognition error. Use your password; retrying later."];
            });
        }
    }
}
- (void)process:(fg::FaceResult)r {
    double now = fg::clockNow(); _lastAcceptedFrame = now;
    if (now - r.observation.captured > 0.35) { _gate.reset(now, _gate.direction()); return; }
    if (_enrolling) {
        if (fg::session().locked) { [self cancel:nil]; return; }
        if (!r.usable || std::abs(r.observation.pose) > 0.18 || now - _sampleAt < 0.45) return;
        if (!_samples.empty() && fg::cosine(_samples.front(), r.embedding) < 0.60) {
            [self setMessage:@"Face changed during enrollment. Keep only yourself in view."]; return;
        }
        _samples.push_back(r.embedding); _sampleAt = now;
        [self setMessage:[NSString stringWithFormat:@"Captured %zu of 8 samples. Slightly vary your angle.", _samples.size()]];
        if (_samples.size() >= 8) {
            fg::Embedding mean{};
            for (const auto &sample : _samples) for (size_t i = 0; i < mean.size(); ++i) mean[i] += sample[i];
            NSError *error = nil;
            if (fg::normalize(mean) && fg::saveOwner(mean, &error)) {
                _owner = mean; _hasOwner = true;
                // A new identity invalidates previous recognition tests and unlock setup.
                NSUserDefaults *p = NSUserDefaults.standardUserDefaults;
                [p setBool:NO forKey:@"experimentalUnlock"]; [p removeObjectForKey:@"testedAppBuild"];
                _unlock.state = NSControlStateValueOff;
                [self cancel:nil]; [self setMessage:@"Face enrolled. Test recognition before enabling experimental unlock."];
            } else { [self cancel:nil]; [self setMessage:error.localizedDescription ?: @"Could not save enrollment."]; }
        }
        return;
    }
    if (!_hasOwner) return;
    r.observation.score = r.usable ? fg::cosine(r.embedding, _owner) : -1;
    fg::Stage before = _gate.stage();
    bool passed = _gate.observe(r.observation, now);
    if (_gate.stage() != before) {
        if (_gate.stage() == fg::Stage::turn) [self say:_gate.direction() > 0 ? @"Turn your head slightly to your left." : @"Turn your head slightly to your right."];
        else if (_gate.stage() == fg::Stage::center) [self say:@"Look straight ahead again."];
        else if (_gate.stage() == fg::Stage::acquire) [self setMessage:@"Look straight at the camera. One matching face is required."];
    }
    if (!passed) return;
    if (_testing) {
        [NSUserDefaults.standardUserDefaults setObject:fg::appBuild() forKey:@"testedAppBuild"];
        [NSUserDefaults.standardUserDefaults setObject:fg::osBuild() forKey:@"testedOSBuild"];
        [self cancel:nil]; [self setMessage:@"Recognition and motion check passed. This test does not verify lock-screen submission."];
        return;
    }
    if (!_locked || _attempted) return;
    // Persist the budget before retrieving any credential, so a process crash cannot loop attempts.
    _attempted = true;
    NSUserDefaults *p = NSUserDefaults.standardUserDefaults;
    [p setBool:YES forKey:@"attemptPending"]; [p synchronize];
    NSString *outcome = fg::submitCredential(r.observation.captured, false);
    [self setMessage:outcome];
    if (![p boolForKey:@"experimentalUnlock"]) [self say:@"Face recognized. Use your password to unlock."];
    _frames = false;
}
- (void)unlockChanged:(id)sender {
    (void)sender;
    NSUserDefaults *p = NSUserDefaults.standardUserDefaults;
    if (_unlock.state != NSControlStateValueOn) { [p setBool:NO forKey:@"experimentalUnlock"]; return; }
    _unlock.state = NSControlStateValueOff;
    if (!_hasOwner || ![[p stringForKey:@"testedAppBuild"] isEqual:fg::appBuild()] ||
        ![[p stringForKey:@"testedOSBuild"] isEqual:fg::osBuild()]) {
        [self setMessage:@"Enroll and pass Test recognition on this app/OS build first."]; return;
    }
    [self authorize:@"Configure experimental password-assisted screen unlock" then:^{
        NSAlert *a = [NSAlert new]; a.messageText = @"Enable experimental unlock?";
        a.informativeText = @"FaceGate will save your Mac login password in your local Keychain and attempt to submit it after a webcam match and head movement. Photos, video, or impersonation may fool this system. macOS may block camera access or input while locked. There is one attempt per lock, and OS/app updates disable the feature. A successful recognition test does not prove screen unlock works.\n\nEnter the password for this Mac account:";
        NSSecureTextField *field = [[NSSecureTextField alloc] initWithFrame:NSMakeRect(0, 0, 350, 26)];
        field.placeholderString = @"Mac login password"; a.accessoryView = field;
        [a addButtonWithTitle:@"Save and enable"]; [a addButtonWithTitle:@"Cancel"];
        [a.window makeFirstResponder:field];
        if ([a runModal] != NSAlertFirstButtonReturn) { field.stringValue = @""; return; }
        NSString *password = field.stringValue; field.stringValue = @"";
        NSError *error = nil;
        if (password.length == 0 || password.length > 128 || !fg::verifyPassword(password, &error)) {
            alert(@"Password not saved", error.localizedDescription ?: @"Use a valid password of 1–128 characters."); return;
        }
        if (fg::session().locked) return;
        if (!fg::keychainWrite(@"login-password", [password dataUsingEncoding:NSUTF8StringEncoding], &error)) {
            alert(@"Keychain error", error.localizedDescription ?: @"Could not store your password."); return;
        }
        NSDictionary *options = @{(__bridge NSString *)kAXTrustedCheckOptionPrompt:@YES};
        AXIsProcessTrustedWithOptions((__bridge CFDictionaryRef)options);
        [p setObject:fg::osBuild() forKey:@"allowedOSBuild"];
        [p setObject:fg::appBuild() forKey:@"allowedAppBuild"];
        [p setBool:YES forKey:@"experimentalUnlock"]; self->_unlock.state = NSControlStateValueOn;
        [self setMessage:@"Allow FaceGate under Privacy & Security → Accessibility. Lock with Control–Command–Q, wake the screen, and follow the spoken head-turn prompt. Password fallback remains available."];
    }];
}
- (void)deleteData:(id)sender {
    (void)sender;
    [self authorize:@"Delete FaceGate's saved face and password" then:^{
        [self cancel:nil]; NSError *first = nil; NSError *second = nil;
        bool a = fg::keychainDelete(@"owner-template", &first);
        bool b = fg::keychainDelete(@"login-password", &second);
        NSUserDefaults *p = NSUserDefaults.standardUserDefaults;
        [p setBool:NO forKey:@"experimentalUnlock"]; [p setBool:NO forKey:@"warmCamera"];
        [p removeObjectForKey:@"testedAppBuild"]; self->_unlock.state = NSControlStateValueOff;
        self->_warm.state = NSControlStateValueOff;
        if (a) { self->_hasOwner = false; self->_owner.fill(0); }
        [self setMessage:a && b ? @"Saved face and password deleted." : (first ?: second).localizedDescription];
        [self tick:nil];
    }];
}
- (void)stop:(id)sender {
    (void)sender; _paused = true; [self stopCamera];
    // launchctl bootout also terminates this process when the Homebrew job owns it.
    NSTask *task = [NSTask new]; task.executableURL = [NSURL fileURLWithPath:@"/bin/launchctl"];
    task.arguments = @[@"bootout", [NSString stringWithFormat:@"gui/%u/homebrew.mxcl.facegate", getuid()]];
    task.standardOutput = NSFileHandle.fileHandleWithNullDevice;
    task.standardError = NSFileHandle.fileHandleWithNullDevice;
    [task launchAndReturnError:nil];
    [NSApp terminate:nil];
}
@end

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        if (argc == 2 && std::strcmp(argv[1], "--version") == 0) { puts("FaceGate 0.1.0"); return 0; }
        if (argc == 2 && std::strcmp(argv[1], "--diagnose") == 0) {
            NSData *json = [NSJSONSerialization dataWithJSONObject:fg::diagnostics() options:NSJSONWritingPrettyPrinted error:nil];
            fwrite(json.bytes, 1, json.length, stdout); puts(""); return 0;
        }
        NSApplication *app = NSApplication.sharedApplication;
        __attribute__((objc_precise_lifetime)) FGApp *delegate = [FGApp new]; app.delegate = delegate;
        [app setActivationPolicy:NSApplicationActivationPolicyAccessory];
        [app run];
    }
    return 0;
}
