//===----------------------------------------------------------------------===//
// Copyright (c) 2026 ReticulumSwift contributors.
//
// Licensed under the Reticulum License. See LICENSE in the repository root for
// the full license text, and NOTICE for attribution of the upstream project
// this file is derived from.
//
// SPDX-License-Identifier: LicenseRef-Reticulum
//===----------------------------------------------------------------------===//

/*
* Copyright (c) 2021-2022, The PurpleI2P Project
*
* This file is part of Purple i2pd project and licensed under BSD3
*
* See full license text in LICENSE file at top of project tree
*/

#ifndef CAPI_H__
#define CAPI_H__

#ifdef __cplusplus
extern "C" {
#endif

// initialization start and stop
void C_InitI2P (int argc, char *argv[], const char * appName);
//void C_InitI2P (int argc, char** argv, const char * appName);
void C_TerminateI2P ();
void C_StartI2P ();
// write system log to logStream, if not specified to <appName>.log in application's folder
void C_StopI2P ();
void C_RunPeerTest (); // should be called after UPnP

#ifdef __cplusplus
}
#endif

#endif
