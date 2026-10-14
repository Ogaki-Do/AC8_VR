// Verified return addresses distinguish the native HUD texture update from
// UEVR's additional viewport update. Mixed/unknown call chains must forward.

// Guarded native vs extra viewport caller paths, derived from verified PE.
static constexpr uintptr_t routeReturns[]={0x4ac778d,0x73011d6};
static constexpr unsigned char routeHeads[2][5]={{0xe8,0xc3,0x69,0x18,0xfd},{0xe8,0xa,0xbe,0xa4,0xfc}};
