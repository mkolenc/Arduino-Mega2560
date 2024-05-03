; signalling.asm
;
; Max Kolenc
; Spring 2024

.include "m2560def.inc"
.cseg
.org 0

; Set up the stack
ldi r17, high(RAMEND)
ldi r16, low(RAMEND)
out SPH, r17
out SPL, r16

; Configure the LEDS for output
ldi r16, 0xFF
out DDRB, r16
sts DDRL, r16

rjmp test_part_e
; Test code

; ****************************************************
; ************** BEGINNING OF TEST CODE **************
; ****************************************************

test_part_a:
	ldi r16, 0b00100001
	rcall set_leds
	rcall delay_long

	clr r16
	rcall set_leds
	rcall delay_long

	ldi r16, 0b00111000
	rcall set_leds
	rcall delay_short

	clr r16
	rcall set_leds
	rcall delay_long

	ldi r16, 0b00100001
	rcall set_leds
	rcall delay_long

	clr r16
	rcall set_leds

	rjmp end

test_part_b:
	ldi r17, 0b00101010
	rcall slow_leds
	ldi r17, 0b00010101
	rcall slow_leds
	ldi r17, 0b00101010
	rcall slow_leds
	ldi r17, 0b00010101
	rcall slow_leds

	rcall delay_long
	rcall delay_long

	ldi r17, 0b00101010
	rcall fast_leds
	ldi r17, 0b00010101
	rcall fast_leds
	ldi r17, 0b00101010
	rcall fast_leds
	ldi r17, 0b00010101
	rcall fast_leds
	ldi r17, 0b00101010
	rcall fast_leds
	ldi r17, 0b00010101
	rcall fast_leds
	ldi r17, 0b00101010
	rcall fast_leds
	ldi r17, 0b00010101
	rcall fast_leds

	rjmp end

test_part_c:
	ldi r16, 0b11111000
	push r16
	rcall leds_with_speed
	pop r16

	ldi r16, 0b11011100
	push r16
	rcall leds_with_speed
	pop r16

	ldi r20, 0b00100000
test_part_c_loop:
	push r20
	rcall leds_with_speed
	pop r20
	lsr r20
	brne test_part_c_loop

	rjmp end

test_part_d:
	ldi r21, 'E'
	push r21
	rcall encode_letter
	pop r21
	push r25
	rcall leds_with_speed
	pop r25

	rcall delay_long

	ldi r21, 'A'
	push r21
	rcall encode_letter
	pop r21
	push r25
	rcall leds_with_speed
	pop r25

	rcall delay_long

	ldi r21, 'M'
	push r21
	rcall encode_letter
	pop r21
	push r25
	rcall leds_with_speed
	pop r25

	rcall delay_long

	ldi r21, 'H'
	push r21
	rcall encode_letter
	pop r21
	push r25
	rcall leds_with_speed
	pop r25

	rcall delay_long

	rjmp end

test_part_e:
	ldi r25, HIGH(WORD02 << 1)
	ldi r24, LOW(WORD02 << 1)
	rcall display_message
	rjmp end

end:
    rjmp end

; ****************************************************
; ***************** END OF TEST CODE *****************
; ****************************************************

; ****************************************************
; ************ BEGINNING OF CODE SECTION *************
; ****************************************************

set_leds:
    push r17
	push r18

	.def port_val = r17
	.def tmp      = r18

	; Hashmap for input
	rjmp MAP_END
    MAP_L: ; Port L
	  .db 0, 128, 32, 160, 8, 136, 40, 168, 2, 130, 34, 162, 10, 138, 42, 170
    MAP_B: ; Port B
      .db 0, 8, 2, 10
  
  MAP_END:
	clr port_val

	; Load Map address into Z pseudo register	
	ldi ZH, high(MAP_L << 1)
	ldi ZL, low(MAP_L << 1)
	
	; Extract PORTL bits from r16 into tmp
	ldi tmp, 0b00001111
	and tmp, r16
	
	; Use tmp as the offset into MAP_L
	add ZL, tmp
	adc ZH, port_val
	
	; Write MAP_L[tmp] to PORTL
	lpm port_val, Z
	sts PORTL, port_val
	
	; Same for PORTB
	clr port_val

	ldi ZH, high(MAP_B << 1)
	ldi ZL, low(MAP_B << 1)

	andi r16, 0b00110000
	lsr r16
	lsr r16
	lsr r16
	lsr r16
	add ZL, r16
	adc ZH, port_val

	lpm port_val, Z
	out PORTB, port_val

	.undef port_val
	.undef tmp

	pop r18
	pop r17

	ret

slow_leds:
    push r16

    mov r16, r17
    rcall set_leds
    rcall delay_long
    ldi r16, 0
    rcall set_leds

	pop r16

	ret

fast_leds:
    push r16

    mov r16, r17
    call set_leds
    rcall delay_short
    ldi r16, 0
    rcall set_leds

	pop r16

	ret

leds_with_speed:
    push r16
	push r17
	push ZL
	push ZH

	in ZH, SPH
	in ZL, SPL

	ldd r17, Z+8
	ldi r16, 0b11000000
	and r16, r17
	breq call_fast_leds ; not set
	rcall slow_leds
	rjmp clean_up

  call_fast_leds:
    rcall fast_leds

  clean_up:
    pop ZH
	pop ZL
	pop r17
	pop r16

	ret


; Note -- this function will only ever be tested
; with upper-case letters, but it is a good idea
; to anticipate some errors when programming (i.e. by
; accidentally putting in lower-case letters). Therefore
; the loop does explicitly check if the hyphen/dash occurs,
; in which case it terminates with a code not found
; for any legal letter.

encode_letter:
    push r0 ; for mul
	push r1 ; for mul
	push r16
	push ZH
	push ZL

	.def tmp = r16

	in ZH, SPH
	in ZL, SPL

	; Calculate the offset into Patterns
	ldi tmp, 'A' 
	ldd r25, Z+9
	sub r25, tmp      ; r25 = input_char - 'A'
	ldi tmp, 8
	mul r25, tmp       ; offset in r1:r0

	; Set Z to point to the start of the pattern
	ldi ZH, high(PATTERNS << 1)
	ldi ZL, low(PATTERNS << 1)
	add ZL, r0
	adc ZH, r1
	adiw ZH:ZL, 1

	; Write pattern to r25 (result)
	ldi tmp, 1 << 5
	mov r0, tmp  ; mask (r0)
	clr r1       ; counter
	clr r25      ; result

  loop:
    inc r1
	lpm tmp, Z+
	cpi tmp, 'o'
	brne LABEL1
	or r25, r0  ; sets bit in r25

  LABEL1:
    lsr r0
	mov tmp, r1
	cpi tmp, 6
	brne loop

	; Write duration to r25 (result)
	lpm tmp, Z
	cpi tmp, 1
	brne LABEL2
	ori r25, 0b11000000 ; set long delay

  LABEL2:
	.undef tmp

    pop ZL
	pop ZH
	pop r16
	pop r1
	pop r0

	ret

display_message:
	push r16
	push r25
	push ZL
	push ZH

	mov ZH, r25
	mov ZL, r24

  LOOP2:
	lpm r16, Z+

	push r16
	rcall encode_letter
	pop r16
	push r25
	rcall leds_with_speed
	pop r25

	cpi r16, 0
	brne LOOP2

	pop ZH
	pop ZL
	pop r25
	pop r16

	ret

; about one second
delay_long:
	push r16

	ldi r16, 14
delay_long_loop:
	rcall delay
	dec r16
	brne delay_long_loop

	pop r16
	ret

; about 0.25 of a second
delay_short:
	push r16

	ldi r16, 4
delay_short_loop:
	rcall delay
	dec r16
	brne delay_short_loop

	pop r16
	ret

; When wanting about a 1/5th of a second delay, all other
; code must call this function
;
delay:
	rcall delay_busywait
	ret

; This function is ONLY called from "delay", and
; never directly from other code. Really this is
; nothing other than a specially-tuned triply-nested
; loop. It provides the delay it does by virtue of
; running on a mega2560 processor.
;
delay_busywait:
	push r16
	push r17
	push r18

	ldi r16, 0x08
delay_busywait_loop1:
	dec r16
	breq delay_busywait_exit

	ldi r17, 0xff
delay_busywait_loop2:
	dec r17
	breq delay_busywait_loop1

	ldi r18, 0xff
delay_busywait_loop3:
	dec r18
	breq delay_busywait_loop2
	rjmp delay_busywait_loop3

delay_busywait_exit:
	pop r18
	pop r17
	pop r16
	ret

; ****************************************************
; *************** END OF CODE SECTION ****************
; ****************************************************

; Some tables

PATTERNS:
	; LED pattern shown from left to right: "." means off, "o" means
    ; on, 1 means long/slow, while 2 means short/fast.
	.db "A", "..oo..", 1
	.db "B", ".o..o.", 2
	.db "C", "o.o...", 1
	.db "D", ".....o", 1
	.db "E", "oooooo", 1
	.db "F", ".oooo.", 2
	.db "G", "oo..oo", 2
	.db "H", "..oo..", 2
	.db "I", ".o..o.", 1
	.db "J", ".....o", 2
	.db "K", "....oo", 2
	.db "L", "o.o.o.", 1
	.db "M", "oooooo", 2
	.db "N", "oo....", 1
	.db "O", ".oooo.", 1
	.db "P", "o.oo.o", 1
	.db "Q", "o.oo.o", 2
	.db "R", "oo..oo", 1
	.db "S", "....oo", 1
	.db "T", "..oo..", 1
	.db "U", "o.....", 1
	.db "V", "o.o.o.", 2
	.db "W", "o.o...", 2
	.db "W", "oo....", 2
	.db "Y", "..oo..", 2
	.db "Z", "o.....", 2
	.db "-", "o...oo", 1   ; Just in case!

WORD00: .db "HELLOWORLD", 0, 0
WORD01: .db "THE", 0
WORD02: .db "QUICK", 0
WORD03: .db "BROWN", 0
WORD04: .db "FOX", 0
WORD05: .db "JUMPED", 0, 0
WORD06: .db "OVER", 0, 0
WORD07: .db "THE", 0
WORD08: .db "LAZY", 0, 0
WORD09: .db "DOG", 0
