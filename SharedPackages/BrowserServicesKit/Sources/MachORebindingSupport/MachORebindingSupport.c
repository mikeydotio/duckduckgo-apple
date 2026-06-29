//
//  MachORebindingSupport.c
//
//  Copyright © 2026 DuckDuckGo. All rights reserved.
//
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//  http://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//

#include "MachORebindingSupport.h"

#if __has_include(<ptrauth.h>)
#include <ptrauth.h>
#endif

uintptr_t BSKStripFunctionPointer(const void *pointer) {
#if defined(__arm64e__) && __has_feature(ptrauth_calls)
    return (uintptr_t)ptrauth_strip(pointer, ptrauth_key_function_pointer);
#else
    return (uintptr_t)pointer;
#endif
}

void *BSKSignFunctionPointer(const void *pointer) {
#if defined(__arm64e__) && __has_feature(ptrauth_calls)
    return ptrauth_sign_unauthenticated((void *)pointer, ptrauth_key_function_pointer, 0);
#else
    return (void *)pointer;
#endif
}

void *BSKSignInstructionPointer(const void *pointer, uintptr_t discriminator) {
#if defined(__arm64e__) && __has_feature(ptrauth_calls)
    return ptrauth_sign_unauthenticated((void *)pointer, ptrauth_key_asia, discriminator);
#else
    (void)discriminator;
    return (void *)pointer;
#endif
}
