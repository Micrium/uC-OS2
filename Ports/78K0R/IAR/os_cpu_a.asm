;********************************************************************************************************
;                                              uC/OS-II
;                                        The Real-Time Kernel
;
;                    Copyright 1992-2021 Silicon Laboratories Inc. www.silabs.com
;
;                                 SPDX-License-Identifier: APACHE-2.0
;
;               This software is subject to an open source license and is distributed by
;                Silicon Laboratories Inc. pursuant to the terms of the Apache License,
;                    Version 2.0 available at www.apache.org/licenses/LICENSE-2.0.
;
;********************************************************************************************************

;********************************************************************************************************
;
;                                        NEC 78K0R Specific code
;                                 IAR C/C++ Compiler for NEC 78K0R 4.60A
;
; Filename : os_cpu_a.asm
; Version  : V2.93.01
;********************************************************************************************************

;********************************************************************************************************
;                                  PUBLIC AND EXTERNAL DECLARATIONS
;********************************************************************************************************

        PUBLIC  OSStartHighRdy
        PUBLIC  OSCtxSw
        PUBLIC  OSIntCtxSw
        PUBLIC  OSTickISR
        EXTERN  OSTaskSwHook
        EXTERN  OSTCBHighRdy
        EXTERN  OSRunning
        EXTERN  OSTCBCur
        EXTERN  OSPrioCur
        EXTERN  OSPrioHighRdy
        EXTERN  OSIntEnter
        EXTERN  OSTimeTick
        EXTERN  OSIntExit
        EXTERN  OSIntNesting
        EXTERN  Tmr_TickISR_Handler         ; implement function to clear the OS tick source

;********************************************************************************************************
;                                           MACRO DEFINITIONS
;********************************************************************************************************

PUSHALL  MACRO
         PUSH   RP0
         PUSH   RP1
         PUSH   RP2
         PUSH   RP3
         MOV    A, CS                 ; Save CS register.
         XCH    A, X
         MOV    A, ES                 ; Save ES register.
         PUSH   AX
         ENDM

POPALL   MACRO
         POP    AX                    ; Restore the ES register.
         MOV    ES, A
         XCH    A, X                  ; Restore the CS register.
         MOV    CS, A
         POP    RP3
         POP    RP2
         POP    RP1
         POP    RP0
         ENDM

        ASEGN   RCODE:CODE, 0x002C
        DW      OSTickISR                   ; Time tick vector

        ASEGN   RCODE:CODE, 0x007E
        DW      OSCtxSw                     ; Context Switch vector

        RSEG    CODE                        ; Program code

;********************************************************************************************************
;                                  START HIGHEST PRIORITY READY TASK
;
; Description: This function is called by OSStart() to start the highest priority task that is ready to run.
;
; Note       : OSStartHighRdy() MUST:
;                 a) Call OSTaskSwHook() then,
;                 b) Set OSRunning to TRUE,
;                 c) Switch to the highest priority task.
;********************************************************************************************************

OSStartHighRdy:

        CALL    OSTaskSwHook                ; call OSTaskSwHook()
        MOVW    RP1, OSTCBHighRdy           ; address of OSTCBHighRdy in RP1
        MOVW    RP0, 0x0000[RP1]            ; RP0 = OSTCBHighRdy->OSTCBStkPtr
        MOVW    SP, RP0                     ; stack pointer = RP0

        MOV     OSRunning, #0x01            ; OSRunning = True

        POPALL                              ; restore all processor registers from new task's stack

        RETI                                ; return from interrupt

;********************************************************************************************************
;                                     TASK LEVEL CONTEXT SWITCH
;
; Description: This function is called by OS_Sched() to perform a task level context switch.
;
; Note       : OSCtxSw() MUST:
;                 a) Save the current task's registers onto the current task stack
;                 b) Save the SP into the current task's OS_TCB
;                 c) Call OSTaskSwHook()
;                 d) Copy OSPrioHighRdy to OSPrioCur
;                 e) Copy OSTCBHighRdy to OSTCBCur
;                 f) Load the SP with OSTCBHighRdy->OSTCBStkPtr
;                 g) Restore all the registers from the high priority task stack
;                 h) Perform a return from interrupt
;********************************************************************************************************

OSCtxSw:

        PUSHALL                             ; save processor registers on the stack

                                            ; save current task's stack pointer into current task's OS_TCB
        MOVW    RP2, OSTCBCur               ; OSTCBCur in RP2
        MOVW    RP0, SP
        MOVW    [RP2], RP0                  ; OSTCBCur->OSTCBStkPtr = SP

        CALL    OSTaskSwHook                ; call OSTaskSwHook

        MOVW    RP0, OSTCBHighRdy           ; get address of OSTCBHighRdy
        MOVW    OSTCBCur, RP0               ; OSTCBCur = OSTCBHighRdy

        MOV     R1, OSPrioHighRdy
        MOV     OSPrioCur, R1               ; OSPrioCur = OSPrioHighRdy

        MOVW    RP1, OSTCBHighRdy           ; get address of OSTCBHighRdy
        MOVW    RP0, 0x0000[RP1]            ; RP0 = OSTCBHighRdy->OSTCBStkPtr
        MOVW    SP, RP0                     ; stack pointer = RP0

        POPALL                              ; restore all processor registers from new task's stack

        RETI                                ; return from interrupt

;********************************************************************************************************
;                                       ISR LEVEL CONTEXT SWITCH
;
; Description: This function is called by OSIntExit() to perform an ISR level context switch.
;
; Note       : OSIntCtxSw() MUST:
;                 a) Call OSTaskSwHook()
;                 b) Copy OSPrioHighRdy to OSPrioCur
;                 c) Copy OSTCBHighRdy to OSTCBCur
;                 d) Load the SP with OSTCBHighRdy->OSTCBStkPtr
;                 e) Restore all the registers from the high priority task stack
;                 f) Perform a return from interrupt
;********************************************************************************************************

OSIntCtxSw:
        CALL    OSTaskSwHook                ; call OSTaskSwHook

        MOVW    RP0, OSTCBHighRdy           ; get address of OSTCBHighRdy
        MOVW    OSTCBCur, RP0               ; OSTCBCur = OSTCBHighRdy

        MOV     R1, OSPrioHighRdy
        MOV     OSPrioCur, R1               ; OSPrioCur = OSPrioHighRdy

        MOVW    RP1, OSTCBHighRdy           ; get address of OSTCBHighRdy
        MOVW    RP0, 0x0000[RP1]            ; RP0 = OSTCBHighRdy->OSTCBStkPtr
        MOVW    SP, RP0                     ; stack pointer = RP0

        POPALL                              ; restore all processor registers from new task's stack

        RETI                                ; return from interrupt

;********************************************************************************************************
;                                              TICK ISR
;
; Description: This ISR handles tick interrupts.  This ISR uses the Watchdog timer as the tick source.
;
; Notes      : 1) The following C pseudo-code describes the operations being performed in the code below.
;
;                 Save all the CPU registers
;                 if (OSIntNesting == 0) {
;                     OSTCBCur->OSTCBStkPtr = SP;
;                     SP                    = OSISRStkPtr;  /* Use the ISR stack from now on           */
;                 }
;                 OSIntNesting++;
;                 Enable interrupt nesting;                 /* Allow nesting of interrupts (if needed) */
;                 Clear the interrupt source;
;                 OSTimeTick();                             /* Call uC/OS-II's tick handler            */
;                 DISABLE general interrupts;               /* Must DI before calling OSIntExit()      */
;                 OSIntExit();
;                 if (OSIntNesting == 0) {
;                     SP = OSTCBHighRdy->OSTCBStkPtr;       /* Restore the current task's stack        */
;                 }
;                 Restore the CPU registers
;                 Return from interrupt.
;
;              2) ALL ISRs should be written like this!
;
;              3) You MUST disable general interrupts BEFORE you call OSIntExit() because an interrupt
;                 COULD occur just as OSIntExit() returns and thus, the new ISR would save the SP of
;                 the ISR stack and NOT the SP of the task stack.  This of course will most likely cause
;                 the code to crash.  By disabling interrupts BEFORE OSIntExit(), interrupts would be
;                 disabled when OSIntExit() would return.  This assumes that you are using OS_CRITICAL_METHOD
;                 #3 (which is the prefered method).
;
;              4) If you DON'T use a separate ISR stack then you don't need to disable general interrupts
;                 just before calling OSIntExit().  The pseudo-code for an ISR would thus look like this:
;
;                 Save all the CPU registers
;                 if (OSIntNesting == 0) {
;                     OSTCBCur->OSTCBStkPtr = SP;
;                 }
;                 OSIntNesting++;
;                 Enable interrupt nesting;                 /* Allow nesting of interrupts (if needed) */
;                 Clear the interrupt source;
;                 OSTimeTick();                             /* Call uC/OS-II's tick handler            */
;                 OSIntExit();
;                 Restore the CPU registers
;                 Return from interrupt.
;********************************************************************************************************

OSTickISR:

        PUSHALL                             ; Save processor registers on the stack

        INC     OSIntNesting                ; increment OSIntNesting
        CMP     OSIntNesting, #1            ; if OSIntNesting != 1
        BNZ     OSTickISR1                  ; jump to OSTickISR1

                                            ; else

        MOVW    RP2, OSTCBCur               ; OSTCBCur in RP2
        MOVW    RP0, SP
        MOVW    [RP2], RP0                  ; OSTCBCur->OSTCBStkPtr = SP

OSTickISR1:

        CALL    Tmr_TickISR_Handler         ; clear timer interrupt source

        CALL    OSTimeTick                  ; call OSTimeTick()

        CALL    OSIntExit                   ; call OSIntExit()

        POPALL                              ; restore all processor registers from stack

        RETI                                ; return from interrupt

        END
