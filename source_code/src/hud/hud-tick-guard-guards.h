// Verified return addresses distinguish the native HUD texture update from
// UEVR's additional viewport update. Mixed/unknown call chains must forward.

// Guarded native vs extra viewport caller paths, derived from verified PE.
static constexpr uintptr_t routeReturns[]={0x4ab979d,0x72ed9d6};
static constexpr unsigned char routeHeads[2][5]={{0xe8,0x63,0x9b,0x18,0xfd},{0xe8,0x9a,0x41,0xa5,0xfc}};
