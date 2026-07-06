//
//  BRImages.m — shared image registry.
//
//  Any feature that wants an image (titlebar strip, glass surfaces, traffic lights, …) reads it
//  from here by role. The bytes travel the same sandbox-safe channel the exclusion lists use:
//  the CLI downscales + base64-encodes each image and writes a { role : base64 } dictionary to a
//  global-domain key; on each config refresh we decode changed entries into cached CGImages and
//  drop removed ones. Features just call BRImageForRole(@"glass"); no per-feature transport.
//

#import <AppKit/AppKit.h>
#import <QuartzCore/QuartzCore.h>
#import "BRConfig.h"

static NSMutableDictionary<NSString *, NSString *> *sB64  = nil;   // role -> base64 (change detection)
static NSMutableDictionary<NSString *, id>         *sImg  = nil;   // role -> (id)CGImageRef (dict-retained)

static CGImageRef BRDecode(NSString *b64) {
    CGImageRef img = NULL;
    @try {
        NSData *d = [[NSData alloc] initWithBase64EncodedString:b64
                                   options:NSDataBase64DecodingIgnoreUnknownCharacters];
        NSBitmapImageRep *rep = d ? [NSBitmapImageRep imageRepWithData:d] : nil;
        if (rep.CGImage) img = CGImageRetain(rep.CGImage);
    } @catch (__unused NSException *e) { img = NULL; }
    return img;
}

// Re-read the { role : base64 } registry from the global domain and reconcile the cache. Decodes
// only entries whose base64 changed; releases roles that disappeared. Cheap on no-op refreshes.
void BRImagesRefresh(void) {
    if (!sB64) { sB64 = [NSMutableDictionary new]; sImg = [NSMutableDictionary new]; }

    CFPropertyListRef v = CFPreferencesCopyValue(CFSTR("com.tweak.brutalium.images"),
                              kCFPreferencesAnyApplication, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
    NSDictionary *reg = ([(__bridge id)v isKindOfClass:[NSDictionary class]]) ? (__bridge NSDictionary *)v : nil;

    for (NSString *role in [sB64 allKeys]) {                     // drop roles no longer present
        if (!reg[role]) { [sB64 removeObjectForKey:role]; [sImg removeObjectForKey:role]; }
    }
    for (NSString *role in reg) {                                // add / update changed roles
        NSString *b64 = reg[role];
        if (![b64 isKindOfClass:[NSString class]] || b64.length == 0) {
            [sB64 removeObjectForKey:role]; [sImg removeObjectForKey:role]; continue;
        }
        if ([sB64[role] isEqualToString:b64]) continue;         // unchanged — keep cache
        CGImageRef img = BRDecode(b64);
        if (img) {
            sB64[role] = [b64 copy];
            [sImg setObject:(__bridge id)img forKey:role];       // dict retains
            CGImageRelease(img);
        }
    }
    if (v) CFRelease(v);
}

CGImageRef BRImageForRole(NSString *role) {
    return (sImg && role) ? (__bridge CGImageRef)sImg[role] : NULL;
}
