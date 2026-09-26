// On laptops with two GPUs (NVIDIA Optimus, AMD switchable graphics) the driver runs a program on the
// power-saving integrated GPU unless the executable exports these flags asking for the fast one.
#include "CGPUPreference.h"

#if defined(_WIN32)
__declspec(dllexport) unsigned long NvOptimusEnablement = 0x00000001;
__declspec(dllexport) int AmdPowerXpressRequestHighPerformance = 1;

int dinocraft_prefers_discrete_gpu(void) {
    return NvOptimusEnablement == 1 && AmdPowerXpressRequestHighPerformance == 1;
}
#else
int dinocraft_prefers_discrete_gpu(void) { return 0; }
#endif
