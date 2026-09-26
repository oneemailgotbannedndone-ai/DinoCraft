#ifndef CGPU_PREFERENCE_H
#define CGPU_PREFERENCE_H

/// Returns 1 when the executable asks laptop drivers for the discrete (NVIDIA or AMD) GPU.
/// Calling it also keeps the exported flags below from being dropped by the linker.
int dinocraft_prefers_discrete_gpu(void);

#endif
