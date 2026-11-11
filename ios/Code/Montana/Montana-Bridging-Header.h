// Bridging header — MontanaBindings/WebRTC are Swift modules.
// The canonical protocol boundary belongs to the app's physical iOS device slice only.
#include <TargetConditionals.h>
#if TARGET_OS_IOS && !TARGET_OS_MACCATALYST && !TARGET_OS_SIMULATOR
#include "montana_core.h"
#endif
