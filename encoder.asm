include /masm64/include64/masm64rt.inc

.const
; Filenames
input_file db "input.dat", 0
output_file db "encoded.dat", 0

.data?
hInput dq ?
hOutput dq ?
read_count dq ? ; Number of bytes ReadFile has read

.data
bRead db 0 ; Byte that was read
bToWrite db 0 ; Byte to be written
bRemainder db 0 ; Remainder of bits to write
nRemainderSize db 0 ; Bits count in the remainder
nEncodedSize dq 0 ; Bits count in encoded data

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

; AX - encoded result
; CL - shifting
; BX - loops
; DX - Read data (During data processing)

; Data segments:
; - Bits count in the last byte
; - Encoded data

    ; Reserve byte for saving the remainder bits count
    mov bToWrite, 0
    invoke WriteFile, hOutput, addr bToWrite, 1, NULL, NULL
    ; Main encoding loop
m0:
; Read byte from the file
    invoke ReadFile, hInput, addr bRead, 1, addr read_count, NULL
    mov al, bRemainder ; Load reminder into memory
    mov bl, nRemainderSize ; Set start bits count
    mov nEncodedSize, rbx

; Processing of the last byte
    cmp read_count, 1
    je m1 ; Byte was read. Handling

    ; Else - Prepare the remainder, write and exit
    mov cl, 8
    sub cl, nRemainderSize ; 8 - Rem. size = Count of bits to shift
    shl al, cl ; Move to the left
    mov bToWrite, al
    ; Write and exit
    invoke WriteFile, hOutput, addr bToWrite, 1, NULL, NULL
    ; Save remainder's bits count
    invoke SetFilePointer, hOutput, 0, NULL, FILE_BEGIN
    ; Remainder size is 0 or the size itself (from the last iteration)
    invoke WriteFile, hOutput, addr nRemainderSize, 1, NULL, NULL
    jmp exit

m1:
; Processing data
    ; Prepare metadata
    mov cl, 6 ; shift size (>> 6, >> 4, >> 2, >> 0)
    mov bl, 4 ; Repeat 4 times (For each pair of bits)

; Encoding loop
m2:
    cmp bl, 0
    je m3 ; End of encoding

    mov dl, bRead ; Data that has to be processed
    shr dl, cl ; Move bits to the beginning to mask them
    and dl, 3 ; Masked bits for processing

    ; Determination of bits sequence and write encoded bits
    ; 00 -> 0
    cmp dl, 0
    jne seq1
    shl rax, 1 ; add 0 to the encoded sequence
    add nEncodedSize, 1 ; Increase size by encoded bits count
    jmp seq_end
    ; 01 -> 10
seq1:
    cmp dl, 1
    jne seq2
    shl rax, 2 ; add 10 to the encoded sequence
    or rax, 2
    add nEncodedSize, 2 ; Increase size by encoded bits count
    jmp seq_end
    ; 10 -> 110
seq2:
    cmp dl, 2
    jne seq3
    shl rax, 3 ; add 110 to the encoded sequence
    or rax, 6
    add nEncodedSize, 3 ; Increase size by encoded bits count
    jmp seq_end
    ; 11 -> 111
seq3:
    ; Don't need to compare. This is the last possible case
    shl rax, 3 ; add 111 to the encoded sequence
    or rax, 7
    add nEncodedSize, 3 ; Increase size by encoded bits count

    ; end of the condifion and loop
seq_end:
    dec bl ; --repeat_count
    sub cl, 2 ; shift size -= 2 (Move to the next pair)
    jmp m2

    ; End of encoding
m3:
    xor rbx, rbx ; Writing loops count (0)
    mov rcx, nEncodedSize

    ; Can't write if size < 8. Moving to the remainder and repeating loop
    cmp rcx, 8
    jge @f
    mov bRemainder, al
    mov nRemainderSize, cl
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
    mov nRemainderSize, cl ; Save remainder size for the next reading loop
; Preparing mask for the remainder
    xor dl, dl ; 0000 0000
    not dl ; 1111 1111
    shl dl, cl ; 1111 1000
    not dl ; 0000 0111

; Save the remainder for the next reading loop
    and dl, al
    mov bRemainder, dl

    shr rax, cl ; Remove remainder from the encoded data
    mov r12, rax ; Swap rax, r12. Now r12 contains encoded data (Because of invoke will rewrite rcx-r11)

; Write each byte in loop
    ; rax - encoded data for processing
    ; rbx - loops count
    ; rcl - shifts count
    ; r11 - encoded data
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