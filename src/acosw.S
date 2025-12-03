.text
.globl acosw
#if defined(__APPLE__)
#else
.type  acosw, @function
#endif
#if defined(__i386__) || defined(__x86_64__)
.intel_syntax noprefix
#endif
acosw:
/*
    extern void acosw(aco_t* from_co, aco_t* to_co);

    struct aco_t {
        void*  reg[X];
        // ...
    }
     
    reference:
        https://github.com/hjl-tools/x86-psABI/wiki/X86-psABI

    pitfall:
        http://man7.org/linux/man-pages/man7/signal.7.html
        http://man7.org/linux/man-pages/man2/sigaltstack.2.html

        > $ man 7 signal
        > ...
        > By default, the signal handler is invoked on the normal process 
        > stack.   It  is  possible  to arrange that the signal handler 
        > uses an alternate stack; see sigaltstack(2) for a discussion of 
        > how to do this and when it might be useful.
        > ...

        This is a BUG example: 
            https://github.com/Tencent/libco/blob/v1.0/coctx_swap.S#L27

    proof of correctness:
        https://github.com/hnes/libaco

    mxcsr & fpu:
        fnstcw * m2byte
            Store FPU control word to m2byte without checking for 
            pending unmasked floating-point exceptions.
        
        fldcw m2byte
            Load FPU control word from m2byte.

        stmxcsr m32
            Store contents of MXCSR register to m32

        ldmxcsr m32
            Load MXCSR register from m32.
*/
/*
    0x00             -->               0xff
    eip esp ebp edi esi ebx fpucw16 mxcsr32
    0   4   8   c   10  14  18      1c
*/
#ifdef __i386__
    mov     eax,DWORD PTR [esp+0x4]     // from_co
    mov     edx,DWORD PTR [esp]         // retaddr
    lea     ecx,[esp+0x4]               // esp
    mov     DWORD PTR [eax+0x8],ebp     //<ebp
    mov     DWORD PTR [eax+0x4],ecx     //<esp
    mov     DWORD PTR [eax+0x0],edx     //<retaddr
    mov     DWORD PTR [eax+0xc],edi     //<edi
    mov     ecx,DWORD PTR [esp+0x8]     // to_co
    mov     DWORD PTR [eax+0x10],esi    //<esi
    mov     DWORD PTR [eax+0x14],ebx    //<ebx
#ifndef ACO_CONFIG_SHARE_FPU_MXCSR_ENV
    fnstcw  WORD  PTR [eax+0x18]        //<fpucw
    stmxcsr DWORD PTR [eax+0x1c]        //<mxcsr
#endif
    mov     edx,DWORD PTR [ecx+0x4]     //>esp
    mov     ebp,DWORD PTR [ecx+0x8]     //>ebp
    mov     eax,DWORD PTR [ecx+0x0]     //>retaddr
    mov     edi,DWORD PTR [ecx+0xc]     //>edi
    mov     esi,DWORD PTR [ecx+0x10]    //>esi
    mov     ebx,DWORD PTR [ecx+0x14]    //>ebx
#ifndef ACO_CONFIG_SHARE_FPU_MXCSR_ENV
    fldcw   WORD  PTR     [ecx+0x18]        //>fpucw
    ldmxcsr DWORD PTR     [ecx+0x1c]        //>mxcsr
#endif
    xor     ecx,ecx
    mov     esp,edx
    xor     edx,edx
    jmp     eax
#elif __x86_64__
/*
    0x00                  -->                  0xff
    r12 r13 r14 r15 rip rsp rbx rbp fpucw16 mxcsr32
    0   8   10  18  20  28  30  38  40      44
*/
    // rdi - from_co | rsi - to_co
    mov     rdx,QWORD PTR [rsp]      // retaddr
    lea     rcx,[rsp+0x8]            // rsp
    mov     QWORD PTR [rdi+0x0], r12
    mov     QWORD PTR [rdi+0x8], r13
    mov     QWORD PTR [rdi+0x10],r14
    mov     QWORD PTR [rdi+0x18],r15
    mov     QWORD PTR [rdi+0x20],rdx // retaddr
    mov     QWORD PTR [rdi+0x28],rcx // rsp
    mov     QWORD PTR [rdi+0x30],rbx
    mov     QWORD PTR [rdi+0x38],rbp
#ifndef ACO_CONFIG_SHARE_FPU_MXCSR_ENV
    fnstcw  WORD PTR  [rdi+0x40]
    stmxcsr DWORD PTR [rdi+0x44]
#endif
    mov     r12,QWORD PTR [rsi+0x0]
    mov     r13,QWORD PTR [rsi+0x8]
    mov     r14,QWORD PTR [rsi+0x10]
    mov     r15,QWORD PTR [rsi+0x18]
    mov     rax,QWORD PTR [rsi+0x20] // retaddr
    mov     rcx,QWORD PTR [rsi+0x28] // rsp
    mov     rbx,QWORD PTR [rsi+0x30]
    mov     rbp,QWORD PTR [rsi+0x38]
#ifndef ACO_CONFIG_SHARE_FPU_MXCSR_ENV
    fldcw   WORD PTR      [rsi+0x40]
    ldmxcsr DWORD PTR     [rsi+0x44]
#endif
    mov     rsp,rcx
    jmp     rax
#elif defined(__aarch64__)
/*
    aarch64 ABI:
    - Callee-saved registers: x19-x28, x29(fp), x30(lr)
    - Callee-saved FPU registers: d8-d15
    - Stack pointer: sp (must be 16-byte aligned)
    - Arguments: x0 = from_co, x1 = to_co

    reg layout in aco_t:
    x19 x20 x21 x22 x23 x24 x25 x26 x27 x28 x29(fp) x30(lr) sp d8 d9 d10 d11 d12 d13 d14 d15
    0   8   16  24  32  40  48  56  64  72  80      88      96 104 112 120 128 136 144 152
*/
    // x0 = from_co, x1 = to_co

    // Save callee-saved registers to from_co
    stp     x19, x20, [x0, #0]
    stp     x21, x22, [x0, #16]
    stp     x23, x24, [x0, #32]
    stp     x25, x26, [x0, #48]
    stp     x27, x28, [x0, #64]
    stp     x29, x30, [x0, #80]      // fp and lr
    mov     x2, sp
    str     x2, [x0, #96]           // sp

#ifndef ACO_CONFIG_SHARE_FPU_MXCSR_ENV
    // Save FPU callee-saved registers d8-d15
    stp     d8, d9, [x0, #104]
    stp     d10, d11, [x0, #120]
    stp     d12, d13, [x0, #136]
    stp     d14, d15, [x0, #152]
#endif

    // Restore callee-saved registers from to_co
    ldp     x19, x20, [x1, #0]
    ldp     x21, x22, [x1, #16]
    ldp     x23, x24, [x1, #32]
    ldp     x25, x26, [x1, #48]
    ldp     x27, x28, [x1, #64]
    ldp     x29, x30, [x1, #80]      // fp and lr
    ldr     x2, [x1, #96]           // sp
    mov     sp, x2

#ifndef ACO_CONFIG_SHARE_FPU_MXCSR_ENV
    // Restore FPU callee-saved registers d8-d15
    ldp     d8, d9, [x1, #104]
    ldp     d10, d11, [x1, #120]
    ldp     d12, d13, [x1, #136]
    ldp     d14, d15, [x1, #152]
#endif

    // Return to the new coroutine (x30/lr contains return address)
    ret
#else
    #error "platform not support"
#endif

.globl aco_save_fpucw_mxcsr
#if defined(__APPLE__)
#else
.type  aco_save_fpucw_mxcsr, @function
#endif
#if defined(__i386__) || defined(__x86_64__)
.intel_syntax noprefix
#endif
aco_save_fpucw_mxcsr:
#ifdef __i386__
    mov     eax,DWORD PTR [esp+0x4]     // ptr
    fnstcw  WORD PTR  [eax]
    stmxcsr DWORD PTR [eax+0x4]
    ret
#elif __x86_64__
    fnstcw  WORD PTR  [rdi]
    stmxcsr DWORD PTR [rdi+0x4]
    ret
#elif defined(__aarch64__)
    // aarch64: save d8-d15 FPU callee-saved registers
    // x0 = ptr (array of 8 void* to store d8-d15)
    stp     d8, d9, [x0, #0]
    stp     d10, d11, [x0, #16]
    stp     d12, d13, [x0, #32]
    stp     d14, d15, [x0, #48]
    ret
#else
    #error "platform not support"
#endif

#if defined(__APPLE__)
.globl _abort
.globl _aco_funcp_protector
#else
.globl abort
.globl aco_funcp_protector
#endif

.globl aco_funcp_protector_asm
#if defined(__APPLE__)
#else
.type  aco_funcp_protector_asm, @function
#endif
#if defined(__i386__) || defined(__x86_64__)
.intel_syntax noprefix
#endif
aco_funcp_protector_asm:
#ifdef __i386__
            and     esp,0xfffffff0
    #if defined(__APPLE__)
            call    _aco_funcp_protector
            call    _abort
    #else
        #if defined(__pic__) || defined(__PIC__)
            call    aco_funcp_protector@PLT
            call    abort@PLT
        #else
            call    aco_funcp_protector
            call    abort
        #endif
    #endif
            ret
#elif __x86_64__
            and     rsp,0xfffffffffffffff0
    #if defined(__APPLE__)
            call    _aco_funcp_protector
            call    _abort
    #else
        #if defined(__pic__) || defined(__PIC__)
            call    aco_funcp_protector@PLT
            call    abort@PLT
        #else
            call    aco_funcp_protector
            call    abort
        #endif
    #endif
            ret
#elif defined(__aarch64__)
            // Align stack to 16 bytes (cannot use AND directly on sp)
            mov     x9, sp
            and     x9, x9, #~0xf
            mov     sp, x9
    #if defined(__APPLE__)
            bl      _aco_funcp_protector
            bl      _abort
    #else
        #if defined(__pic__) || defined(__PIC__)
            bl      aco_funcp_protector
            bl      abort
        #else
            bl      aco_funcp_protector
            bl      abort
        #endif
    #endif
            ret
#else
    #error "platform not support"
#endif
