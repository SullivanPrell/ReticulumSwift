/*
 * C API extension for i2pd client services (SAM bridge, address book).
 *
 * This file is maintained in ReticulumSwift, NOT in upstream i2pd: it adds the
 * two entry points the Swift I2P interface needs (declared in
 * Sources/CI2PDCShims/include/capi_client.h). The build (build_ci2pd_ios.sh)
 * compiles it against the pinned i2pd source's headers, so the includes below
 * resolve via the i2pd `-I` paths the build already passes:
 *   ClientContext.h  ->  -I<i2pd>/libi2pd_client
 *   capi_client.h    ->  -I<repo>/Sources/CI2PDCShims/include
 *
 * Call sequence:
 *   C_InitI2P  ->  C_StartI2P  ->  C_StartClientServices
 *   C_StopClientServices  ->  C_StopI2P  ->  C_TerminateI2P
 */

#include "ClientContext.h"
#include "capi_client.h"

#ifdef __cplusplus
extern "C" {
#endif

void C_StartClientServices(void)
{
    i2p::client::context.Start();
}

void C_StopClientServices(void)
{
    i2p::client::context.Stop();
}

#ifdef __cplusplus
}
#endif
