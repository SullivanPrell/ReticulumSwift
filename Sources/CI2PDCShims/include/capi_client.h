/*
 * C API extension: client services (SAM bridge, address book, tunnels).
 * Call C_StartClientServices() after C_StartI2P() to start the SAM bridge on port 7656.
 * Call C_StopClientServices() before C_StopI2P() to cleanly shut down SAM.
 *
 * SAM is enabled by default (sam.enabled=true, sam.port=7656).
 * Pass argv to C_InitI2P with "--sam.port=NNNN" to use a different port.
 */
#ifndef CAPI_CLIENT_H__
#define CAPI_CLIENT_H__

#ifdef __cplusplus
extern "C" {
#endif

void C_StartClientServices (void);
void C_StopClientServices  (void);

#ifdef __cplusplus
}
#endif

#endif /* CAPI_CLIENT_H__ */
