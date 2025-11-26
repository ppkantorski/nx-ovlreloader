/********************************************************************************
 * File: main.c
 * Author: ppkantorski
 * Description: 
 *   This file contains the main program logic for nx-ovlreloader, a system module
 *   designed to monitor and automatically respawn nx-ovlloader if it exits or is
 *   terminated. It ensures that overlays remain active and allows developers to
 *   reload nx-ovlloader without requiring a full console restart.
 * 
 *   Key Features:
 *   - Monitors the nx-ovlloader process and detects termination.
 *   - Automatically respawns nx-ovlloader after a configurable delay.
 *   - Minimal heap usage and self-contained sysmodule design.
 *   - Compatible with libnx-based homebrew and other sysmodules.
 * 
 *   For the latest updates and contributions, visit the project's GitHub repository.
 *   (GitHub Repository: https://github.com/ppkantorski/nx-ovlloader)
 * 
 *   Note: Please be aware that this notice cannot be altered or removed. It is a part
 *   of the project's documentation and must remain intact.
 *
 *  Licensed under GPLv2
 *  Copyright (c) 2025 ppkantorski
 ********************************************************************************/


#include <switch.h>

#define OVLLOADER_TID 0x420000000007E51AULL
#define CHECK_INTERVAL_NS 10000000ULL    // 10ms - check frequently
#define RESPAWN_DELAY_NS 50000000ULL    // 100ms - wait before respawn
#define TIMEOUT_NS 2000000000ULL         // 2 seconds - give up if process doesn't die
#define INNER_HEAP_SIZE 0x4000

#ifdef __cplusplus
extern "C" {
#endif

// Sysmodules should not use applet*.
u32 __nx_applet_type = AppletType_None;

// Sysmodules will normally only want to use one FS session.
u32 __nx_fs_num_sessions = 1;

// Newlib heap configuration function (makes malloc/free work).
void __libnx_initheap(void) {
    static u8 inner_heap[INNER_HEAP_SIZE];
    extern void* fake_heap_start;
    extern void* fake_heap_end;
    
    // Configure the newlib heap.
    fake_heap_start = inner_heap;
    fake_heap_end = inner_heap + sizeof(inner_heap);
}

// Service initialization.
void __appInit(void) {
    Result rc;
    
    // Initialize SM
    rc = smInitialize();
    if (R_FAILED(rc))
        diagAbortWithResult(MAKERESULT(Module_Libnx, LibnxError_InitFail_SM));
    
    // Get firmware version for hosversionSet
    rc = setsysInitialize();
    if (R_SUCCEEDED(rc)) {
        SetSysFirmwareVersion fw;
        rc = setsysGetFirmwareVersion(&fw);
        if (R_SUCCEEDED(rc))
            hosversionSet(MAKEHOSVERSION(fw.major, fw.minor, fw.micro));
        setsysExit();
    }
    
    // Initialize PM services
    rc = pmdmntInitialize();
    if (R_FAILED(rc))
        diagAbortWithResult(MAKERESULT(Module_Libnx, LibnxError_ShouldNotHappen));
    
    rc = pmshellInitialize();
    if (R_FAILED(rc)) {
        pmdmntExit();
        diagAbortWithResult(MAKERESULT(Module_Libnx, LibnxError_ShouldNotHappen));
    }
    
    // Close SM now that we've initialized everything
    smExit();
}

// Service deinitialization.
void __appExit(void) {
    pmshellExit();
    pmdmntExit();
}

#ifdef __cplusplus
}
#endif

int main(int argc, char **argv) {
    
    Result rc;

#if !BUILDING_NRO_DIRECTIVE
    
    u64 startTick = armGetSystemTick();
    
    // Phase 1: Wait for nx-ovlloader to exit (it should be exiting when we start)
    while (true) {
        // Timeout check
        if (armTicksToNs(armGetSystemTick() - startTick) >= TIMEOUT_NS) {
            // Process didn't exit in time, just exit ourselves
            return 1;
        }
        
        u64 pid = 0;
        rc = pmdmntGetProcessId(&pid, OVLLOADER_TID);
        
        if (R_FAILED(rc) || pid == 0) {
            // Process has exited, proceed to respawn phase
            break;
        }
        
        svcSleepThread(CHECK_INTERVAL_NS);
    }
    
    // Phase 2: Wait the respawn delay
    svcSleepThread(RESPAWN_DELAY_NS);
    
    // Phase 3: Relaunch nx-ovlloader
    NcmProgramLocation programLocation = {
        .program_id = OVLLOADER_TID,
        .storageID = NcmStorageId_None,
    };
    
    u64 newPid = 0;
    pmshellLaunchProgram(0, &programLocation, &newPid);
    
#else
    u64 pid = 0;
    rc = pmdmntGetProcessId(&pid, OVLLOADER_TID);
    
    if (R_SUCCEEDED(rc) && pid != 0) {
        // Kill the existing process
        pmshellTerminateProgram(OVLLOADER_TID);
        
        // Wait briefly for termination to complete
        svcSleepThread(RESPAWN_DELAY_NS);
        
        // Verify it actually terminated before respawning
        u64 checkPid = 0;
        u64 startTick = armGetSystemTick();
        while (true) {
            rc = pmdmntGetProcessId(&checkPid, OVLLOADER_TID);
            if (R_FAILED(rc) || checkPid == 0) {
                // Process terminated successfully
                break;
            }
            
            if (armTicksToNs(armGetSystemTick() - startTick) >= TIMEOUT_NS) {
                // Couldn't kill it, abort
                return 1;
            }
            
            svcSleepThread(CHECK_INTERVAL_NS);
        }
    }
    
    // Now relaunch nx-ovlloader
    NcmProgramLocation programLocation = {
        .program_id = OVLLOADER_TID,
        .storageID = NcmStorageId_None,
    };
    
    u64 newPid = 0;
    pmshellLaunchProgram(0, &programLocation, &newPid);
#endif
    
    // Mission accomplished - exit cleanly
    return 0;
}
