; mycketlitenfärjan - 256b for Revision 2023 ;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

INIT_MIDI_UART equ 0
CHECK_ESC equ 1
org 0x100

;;; INIT STUFF

start:
; AX=0000 BX=0000 CX=00FF DX=CS
; SI=0100 DI=FFFE BP=09xx SP=FFFE
    xor al, 0x13 ; Assuming AX=0. Use xor to make nicer sun circle constant from the instruction :)
    int 10h      ; Set VGA mode, AL now trash
    les bx, [bx] ; Set ES=0x9fff aka 16 bytes before VGA segment

; Fill background with sky color
    mov al, 0x4c
; Have DI end up at -322+16 (16 offset due to LES hack), +2 because initial DI is -2
    mov cx, 0x10000-322+2+16
    rep stosb

; Sun renderer (~31 bytes):
; AL: color
; AH: free
; BX: free
; CX: temp counter (must be 0 on input)
; DX: free
; SI: used as scratch memory pointer
; DI: VGA dest pointer. On enter -322 (off by 2 because shadow) so first sun line will be hidden :D
; BP: free
; SP: free
    fld1 ; constant 1
    fldz ; y=0
    mov al, 0x2c ; yellow

sunloop:
    ; these instructions actually belong to the end of the loop,
    ; but structuring like this saves one jmp (so on 1st iteration must be nop)
    sub di, cx
    insw ; draw sun shadow with black - assumes reading from whatever garbage port in dx results in 0 :)
    rep stosb ; draw sun with yellow
    ; loop actually starts here
    fld st0               ; FPU stack: y, y, 1
    fmul st0, st0         ; FPU stack: y*y, y, 1
    fisubr word [si]      ; FPU stack: radius^2-y*y, y, 1. First word of code used as radius^2 :)
    fsqrt                 ; FPU stack: sqrt(radius^2-y*y), y, 1
flt_y_amount:
    fistp word [bx]       ; FPU stack: y, 1
flt_x_timemul: equ $ + 1
    fadd st0, st1         ; FPU stack: y, 1
    add di, 318  ; -2 because shadow
    add cx, [bx] ; assumes CX=0, use add instead of mov to set flags
    jnl sunloop ; assumes that fistp on sqrt(negative) results in funny value :)
    insw
; Registers for start of main loop:
; AX: sun color (0x2c), AH=0
; BX: 0x20CD (from 'les' trick?)
; CX: 0x8000
; DX: CS
; SI: 0x100
; DI: Pointer to line after sun
; BP: unchanged
; SP: 0xFFFE
;;; MAIN LOOP STUFF

    fldz ; FPU stack: t=0, final y of sun, 1
; Music player:
; AL: temp
; AH: must be 0
; BX: free
; CX: free
; DX: MIDI port (0x330 or 0x331)
; SI: Pointer to notes
; DI: free
; BP: note length counter
; SP: free
reload_song:
    mov si, midi_initdata
    ; increment instrument which also speeds up animation
    inc byte [si+instrument_byte-midi_initdata]
    ; reset to piano near end
    and byte [si+instrument_byte-midi_initdata],0xbf
    ; swap direction on every loop
    ; xor byte [si+fadd_or_fsub-midi_initdata], 0x20

%if INIT_MIDI_UART
    mov dx, 0x331 ; MIDI control port
    outsb
    dec dx ; MIDI data port
    mov cx, end_of_initdata - midi_initdata - 1
%else
    mov dx, 0x330 ; MIDI data Port
    mov cx, end_of_initdata - midi_initdata
%endif
    rep outsb

next_note:
    lodsb ; read from table
    mov bp, ax ; used as note length
    and al, 0x8f ; extract pitch

    jl reload_song ; high bit terminates
    jz skip ; if pause (pitch value == 0), use MIDI pitch 0 (hopefully inaudible :D)
    xor bp, ax ; undo effect of pitch on note length (sounds bit better)
    add al, 65 ; lowest note minus 1
skip:
    out dx, al ; pitch byte

    inc ax ; velocity byte (can be same as pitch, but must not be 0 in case of pause)
    out dx, al

draw_bg:
    pusha

    mov dl, 0xda ; Assuming DX = 0x330 still from MIDI player
wait_vblank:
    in al, dx
    test al, 8
    jz wait_vblank

; grass
    mov al, 0x02
    mov ch, 5*8
    rep stosb
; sea
    mov al, 0x36
    mov ch, 5*24+2   ; di must not be 0, so ret at end works
    rep stosb

draw_farjan:
    ; initialize this here to save on smaller encodings for float constant pointers
    mov si, gfx_data

    ; increment t (on top of stack)
fadd_or_fsub equ $ + 1
    fadd dword [si+flt_timedelta-gfx_data] ; FPU stack: t, sun Y, 1
    fsub dword [si+flt_timedelta2-gfx_data]

    ; push sin(t)
    fld st0                   ; FPU stack: t, t, sun Y, 1
    fsin                      ; FPU stack: sin(t), t, sun Y, 1

    ; multiply by y-constant
    fmul dword [si+flt_y_amount-gfx_data] ; FPU stack: yc*sin(t), t, sun Y, 1
    frndint                               ; FPU stack: round(yc*sin(t)), t, sun Y, 1
    fimul word [si+imm320-gfx_data]       ; FPU stack: 320*round(3.3*sin(t)), t, sun Y, 1

    ; push sin(t)
    fld st1
    fmul dword [si+flt_x_timemul-gfx_data]
    fsin
    fmul st3
    faddp

    fistp word [di]
    mov di, [di]

; Primitive renderer:
; AL: color
; AH: destroyed
; BX: start offset of scanline, in 8.8 fixed point
; CL: temp counter
; CH: must be 0
; DX: width of scanline, in 8.8 fixed point
; SI: source primitives pointer (initializer earlier for smaller encodings)
; DI: VGA dest pointer
; BP: startpos delta
; SP: need to be valid for stack
next_primitive:
    lodsw        ; delta di
    add di, ax
    lodsb        ; delta startPos
    movsx bp, al
    lodsw        ; initial width + color
    mov dx, ax
    mov cl, 15 ; number of rows
primitive_loop:
    pusha ; save di, cx
    movsx bp, bh ; startPos integer part
    add di, bp ; di += int(startPos)
    xchg cl, dh ; cx = int(width)
    rep stosb
    popa ; restore di, cx
imm320 equ $ + 2
    add di, 320
    add dx, [si]   ; increment width (fixed point)
    add bx, bp     ; increment startPos (fixed point)
    loop primitive_loop
    lodsw ; si += 2

    ;cmp si, end_of_gfx
    cmp al, 0x01 ; must match with 2nd last byte of gfx data
    jne next_primitive

    popa
    ; decrement note length
    dec bp
    dec bp
    jl next_note

%if CHECK_ESC
    in al, 0x60 ; check for ESC
    dec al
    jnz draw_bg
%if INIT_MIDI_UART
    ret ; c3 below is ret
%endif
%else
    jmp draw_bg
%endif

midi_initdata:
%if INIT_MIDI_UART
db 0x3F ; uart mode
%endif
db 0xc3 ; instrument for channel 0
flt_timedelta equ $ - 3
instrument_byte:
db 59   ; Instrument, maybe 45,46,106,114 are good self-cancelling ones, 63,80 for monophonic
db 0xb3 ; Channel mode
db 126  ; Mode to mono
flt_timedelta2 equ $-3
db 0x3c  ; FREE BYTE! (almost)
db 0x93 ; note on
end_of_initdata:

note_data:
%define note(pitch, length) db (pitch - 65) | (length << 4)
%define hold(prevpitch, length) db (length << 4)
; used:   66 68 70 71 73 75 76 78 80
; unused: 67 69 72 74 77 79
;         66+ 67- 68+ 69- 70+ 71+ 72- 73+ 74- 75+ 76+ 77- 78+ 79- 80+
note(68, 4)
note(68, 2)
note(71, 2)
hold(71, 2)
note(70, 4)
note(66, 6)
note(66, 4)
note(70, 4)
note(73, 4)
note(71, 4)
note(73, 2)
note(75, 2)
hold(75, 5)
note(78, 1)
hold(78, 1)
note(78, 4)
note(76, 2)
note(76, 2)
hold(76, 5)
note(75, 1)
hold(75, 1)
note(73, 4)
note(75, 2)
note(76, 4)
note(80, 4)
note(78, 6)
hold(78, 2)
end_of_notes:

gfx_data:
; must have high bit set!
;
dw 15 + 320*110 + 98
db -32
dw 1064
dw 288
;
dw -1599
db -128
dw 4126
dw 400
;
dw -4168
db -128
dw 24863
dw 384
;
dw -2253
db -90
dw 7711
dw 0
;
dw -3204
db 120
dw 41000
dw -255
