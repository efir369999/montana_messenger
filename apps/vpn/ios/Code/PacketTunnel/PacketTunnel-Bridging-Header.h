// Exposes the packet pump's C entry points to the extension's Swift. The library is a static
// xcframework, so its header travels through this bridge rather than a module map: two xcframeworks
// cannot both place a module map at the root of the same copied headers directory.
#import "hev-main.h"
