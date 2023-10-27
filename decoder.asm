include /masm64/include64/masm64rt.inc

.const
; Filenames
input_file db "encoded.dat", 0
output_file db "decoded.dat", 0

.data?
hInput dq ?
hOutput dq ?
read_count dq ? ; Number of bytes ReadFile has read

.data
bRead db 0 ; Byte that were read
mInputSize dq 0 ; Size of an input file in bytes
nLastBitsCount db 0 ; Bits count in the last byte

bRemainder dq 0 ; Remainder from bits to write
nRemainderSize db 0 ; Bits count in the remainder
bEncodedData dq 0 ; Encoded data

bDecodedRemainder db 0 ; Remainder from decoded bits
nDecodedRemainderSize db 0 ; Bits count in the decoded remainder

bToWrite db 0 ; Byte to be written

.code
entry_point proc
    ; Opening an input file
    invoke CreateFileA, addr input_file, GENERIC_READ, FILE_SHARE_READ, NULL,\
           OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, NULL
    cmp rax, INVALID_HANDLE_VALUE
    je exit ; If can't open file - exit
    mov hInput, rax ; Save input file handle

    ; Creating an output file
    invoke CreateFileA, addr output_file, GENERIC_WRITE, FILE_SHARE_READ, NULL,\
           CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, NULL
    cmp rax, INVALID_HANDLE_VALUE
    je exit ; If can't open file - exit
    mov hOutput, rax ; Save input file handle

    ; Getting input file size
    invoke GetFileSizeEx, hInput, addr mInputSize
    dec mInputSize ; 1 byte is reserved for the remainder size. Skip
    ; Read bits count in the last byte
    invoke ReadFile, hInput, addr nLastBitsCount, 1, addr read_count, NULL

    ; Main decoding loop
m0:
    cmp mInputSize, 0 ; Decode while there are bytes to decode
    je exit ; End of decoding

    mov r12, bRemainder ; Load reminder into memory
    xor rbx, rbx
    mov bl, nRemainderSize ; Set start bits count

; Read byte from the file
    invoke ReadFile, hInput, addr bRead, 1, addr read_count, NULL
    cmp read_count, 0
    je exit ; Nothing to decode

    ; Process size for the last byte
    .if mInputSize == 1 ; If the byte is last
        add bl, nLastBitsCount ; Add count of read bits
        shl r12, 8
        or r12b, bRead ; Place read bytes
        mov rcx, 8
        sub cl, nLastBitsCount
        shr r12, cl ; Remove redundant zeros
    .else
        add bl, 8 ; Add count of read bits
        shl r12, 8 ; Place read bytes
        or r12b, bRead
    .endif
    dec mInputSize ; Decrease the remaining file size

    mov bEncodedData, r12 ; Save full encoded data
    xor rax, rax
    mov al, bDecodedRemainder ; Saving the decoded data from the previous iteration
    xor r9, r9
    mov r9b, nDecodedRemainderSize; Load to r9 remainder size
    ; Don't need this data anymore
    mov bRemainder, 0
    mov nRemainderSize, 0
m2:
; Shifting and preparing metadata
; rax - decoded bits
; rbx - encoded bits count
; rdx - encoded bits
; r8 - count of bits to take
; r9 - count of encoded bits in rax
    cmp rbx, 0 ; If the size of the remaining encoded data <= 0
    jle end_decode ; No more data to decode. Exit
    cmp rbx, 3
    jg @f ; rbx > 3
    ; rbx - (0; 3]: r8 = rbx
    mov r8, rbx ; Take the remaining bits
    jmp start_decode
@@:
    ; rbx > 3
    mov r8, 3 ; Take 3 bits
start_decode:
    ; Moving bits
    mov rdx, bEncodedData ; Load the encoded data
    mov rcx, rbx
    sub rcx, r8 ; Size - count of bits to take = shifts count
    shr rdx, cl ; Bits are moved to the right border
    ; Masking bits
    mov r10, rdx ; Copy encoded data
    mov rcx, r8 ; rcx - count of bits
    shr rdx, cl
    shl rdx, cl ; erase rcx bits from the right side
    xor rdx, r10 ; mask rcx bits

    ; Process taken bits depending on their count
    .if r8 == 3 ; 3 bits
        .if rdx == 7 ; 111
            shl rax, 2
            or rax, 3 ; Save 11
            sub rbx, 3 ; Decrease ncoded bits count
            add r9, 2 ; Increase decoded bits count
            jmp m2 ; Loop
        .elseif rdx == 6 ; 110
            shl rax, 2
            or rax, 2 ; Save 10
            sub rbx, 3 ; Decrease encoded bits count
            add r9, 2 ; Increase decoded bits count
            jmp m2 ; Loop
        .else
            dec r8 ; Decrease count of bits to take
            jmp start_decode ; Take 2 bits instead
        .endif
    .elseif r8 == 2 ; 2 bits
        .if rdx == 2 ; 10
            shl rax, 2
            or rax, 1 ; Save 01
            sub rbx, 2 ; Decrease encoded bits count
            add r9, 2 ; Increase decoded bits count
            jmp m2 ; Loop
        .elseif rdx == 0 ; 00
            shl rax, 4 ; Save 0000
            sub rbx, 2 ; Decrease encoded bits count
            add r9, 4 ; Increase decoded bits count
            jmp m2 ; Loop
        .elseif rdx == 3 ; 11 - remainder
            mov nRemainderSize, 2 ; 2 bits are in the remainder
            mov bRemainder, 3 ; Save the remainder
            jmp end_decode
        .else ; 01 or 1 or 0
            dec r8 ; Decrease count of bits to take
            jmp start_decode ; Take 2 bits instead
        .endif
    .else ; 1 bit
        .if rdx == 0 ; 0
            shl rax, 2 ; Save 00
            sub rbx, 1 ; Decrease encoded bits count
            add r9, 2 ; Increase decoded bits count
            jmp m2 ; Loop
        .else ; 1
            mov nRemainderSize, 1 ; 1 bit is in the remainder
            mov bRemainder, 1 ; Save the remainder
            jmp end_decode
        .endif
    .endif

end_decode:
    xor rbx, rbx ; Writing loops count (0)
    mov rcx, r9 ; Load size of the decoded data

    ; Can't write if size < 8. Moving to the remainder and repeating loop
    cmp rcx, 8
    jge @f
    mov bDecodedRemainder, al
    mov nDecodedRemainderSize, cl
    jmp m0

; Get write loops count and remainder size
@@:
    cmp rcx, 8
    jl @f
    ; Size >= 8
    inc rbx ; ++write_loops
    sub rcx, 8 ; -1 writable byte from size
    jmp @b

    ; Size < 8
@@:
    mov nDecodedRemainderSize, cl ; Save remainder size for the next reading loop
    ; Masking bits of the remainder
    mov r10, rax ; Copy encoded data
    shr r10, cl
    shl r10, cl ; erase rcx bits from the right side
    xor r10, rax ; mask rcx bits
    mov bDecodedRemainder, r10b

    shr rax, cl ; Remove remainder from the encoded data
    mov r12, rax ; Swap rax, r12. Now r12 contains encoded data (Because of invoke will rewrite rcx-r11)

@@:
    cmp rbx, 0
    je m0 ; End. Perfecto! Next byte, please!

    mov rax, r12
    dec rbx ; -1 loop / shifts count (in bytes)
    mov cl, bl
    imul rcx, 8 ; shifts count (in bits)

    shr rax, cl ; Move the byte to the left
    and rax, 255 ; Mask exacly 1 byte

    mov bToWrite, al ; Final step
    invoke WriteFile, hOutput, addr bToWrite, 1, NULL, NULL
    jmp @b

exit:
    invoke CloseHandle, hInput
    invoke CloseHandle, hOutput
    invoke ExitProcess, 0
entry_point endp
end