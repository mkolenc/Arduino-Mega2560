; LCD_panel.asm
;
; Max Kolenc
; Spring 2024

; ***************************************************
; ******* BEGINNING OF INITIALIZATION SECTION *******
; ***************************************************
;
; In this section are:
; 
; (1) assembler direction setting up the interrupt-vector table
;
; (2) "includes" for the LCD display
;
; (3) some definitions of constants that may be used later in
;     the program
;
; (4) code for initial setup of the Analog-to-Digital Converter
;
; (5) Code for setting up three timers (timers 1, 3, and 4).

.cseg
.org 0
	jmp reset

; Actual .org details for this an other interrupt vectors can be
; obtained from main ATmega2560 data sheet
;
.org 0x22
	jmp timer1

; This included for completeness. Because timer3 is used to
; drive updates of the LCD display, and because LCD routines
; *cannot* be called from within an interrupt handler, we
; will need to use a polling loop for timer3.
;
; .org 0x40
;	jmp timer3

.org 0x54
	jmp timer4

.include "m2560def.inc"
.include "lcd.asm"

.cseg
#define CLOCK 16.0e6
#define DELAY1 0.01
#define DELAY3 0.1
#define DELAY4 0.5

#define BUTTON_RIGHT_MASK 0b00000001	
#define BUTTON_UP_MASK    0b00000010
#define BUTTON_DOWN_MASK  0b00000100
#define BUTTON_LEFT_MASK  0b00000100

#define BUTTON_RIGHT_ADC  0x032
#define BUTTON_UP_ADC     0x0b0   ; was 0x0c3
#define BUTTON_DOWN_ADC   0x160   ; was 0x17c
#define BUTTON_LEFT_ADC   0x22b
#define BUTTON_SELECT_ADC 0x316

.equ PRESCALE_DIV=1024   ; w.r.t. clock, CS[2:0] = 0b101

; TIMER1 is a 16-bit timer. If the Output Compare value is
; larger than what can be stored in 16 bits, then either
; the PRESCALE needs to be larger, or the DELAY has to be
; shorter, or both.
.equ TOP1=int(0.5+(CLOCK/PRESCALE_DIV*DELAY1))
.if TOP1>65535
.error "TOP1 is out of range"
.endif

; TIMER3 is a 16-bit timer. If the Output Compare value is
; larger than what can be stored in 16 bits, then either
; the PRESCALE needs to be larger, or the DELAY has to be
; shorter, or both.
.equ TOP3=int(0.5+(CLOCK/PRESCALE_DIV*DELAY3))
.if TOP3>65535
.error "TOP3 is out of range"
.endif

; TIMER4 is a 16-bit timer. If the Output Compare value is
; larger than what can be stored in 16 bits, then either
; the PRESCALE needs to be larger, or the DELAY has to be
; shorter, or both.
.equ TOP4=int(0.5+(CLOCK/PRESCALE_DIV*DELAY4))
.if TOP4>65535
.error "TOP4 is out of range"
.endif

reset:
; Constant used throughout the program
.def ZERO = r0
	clr ZERO

; Set up the stack
ldi TEMP, low(RAMEND)
ldi TEMP2, high(RAMEND)
out SPL, TEMP
out SPH, TEMP2

; Initilze data in .dseg
ldi TEMP, ' '

sts BUTTON_IS_PRESSED, ZERO
sts LAST_BUTTON_PRESSED, TEMP

ldi YL, low(TOP_LINE_CONTENT)
ldi YH, high(TOP_LINE_CONTENT)
ldi ZL, low(CURRENT_CHARSET_INDEX)
ldi ZH, high(CURRENT_CHARSET_INDEX)

clr TEMP2
init_loop:
  inc TEMP2
  st Y+, TEMP
  st Z+, ZERO
  cpi TEMP2, LCD_COLUMN
  brne init_loop

sts CURRENT_CHAR_INDEX, ZERO

; initialize the ADC converter (which is needed
; to read buttons on shield). Note that we'll
; use the interrupt handler for timer 1 to
; read the buttons (i.e., every 10 ms)
;
ldi temp, (1 << ADEN) | (1 << ADPS2) | (1 << ADPS1) | (1 << ADPS0)
sts ADCSRA, temp
ldi temp, (1 << REFS0)
sts ADMUX, r16

; Timer 1 is for sampling the buttons at 10 ms intervals.
; We will use an interrupt handler for this timer.
ldi r17, high(TOP1)
ldi r16, low(TOP1)
sts OCR1AH, r17
sts OCR1AL, r16
clr r16
sts TCCR1A, r16
ldi r16, (1 << WGM12) | (1 << CS12) | (1 << CS10)
sts TCCR1B, r16
ldi r16, (1 << OCIE1A)
sts TIMSK1, r16

; Timer 3 is for updating the LCD display. We are
; *not* able to call LCD routines from within an 
; interrupt handler, so this timer must be used
; in a polling loop.
ldi r17, high(TOP3)
ldi r16, low(TOP3)
sts OCR3AH, r17
sts OCR3AL, r16
clr r16
sts TCCR3A, r16
ldi r16, (1 << WGM32) | (1 << CS32) | (1 << CS30)
sts TCCR3B, r16
; Notice that the code for enabling the Timer 3
; interrupt is missing at this point.

; Timer 4 is for updating the contents to be displayed
; on the top line of the LCD.
ldi r17, high(TOP4)
ldi r16, low(TOP4)
sts OCR4AH, r17
sts OCR4AL, r16
clr r16
sts TCCR4A, r16
ldi r16, (1 << WGM42) | (1 << CS42) | (1 << CS40)
sts TCCR4B, r16
ldi r16, (1 << OCIE4A)
sts TIMSK4, r16

sei

; ***************************************************
; ********** END OF INITIALIZATION SECTION **********
; ***************************************************

; ****************************************************
; ************* BEGINNING OF CODE ECTION *************
; ****************************************************

rcall lcd_init
rjmp timer3_polling_loop

; **
; timer1:     Checks whether a button has been pressed, and if so, which button it is, 
;             every DELAY1 (0.01) seconds.
;
; Registers:  TEMP - Temporary working register
; 
; Modifies: - LAST_BUTTON_PRESSED.
;           - BUTTON_IS_PRESSED.
; 
; Stack:      None.
; Returns:	  Nothing.
;  
timer1:
    push TEMP
    in TEMP, SREG
    push TEMP

	rcall record_btn_status

	pop TEMP
    out SREG, TEMP
    pop TEMP

	reti

; **
; timer3_polling_loop: Updates the LCD diplay continuously every DELAY3 (0.1) seconds.
;
; Registers:           TEMP - Temporary working register
; 
; Modifies:            None.
; Stack:               None.
; Returns:             Nothing.
;                          
timer3_polling_loop:
	; wait until timer3 has finished
    in TEMP, TIFR3
    sbrs TEMP, OCF3A
    rjmp timer3_polling_loop

	; timer3 has finished, reset its interrupt flag
    ldi TEMP, 1 << OCF3A
    out TIFR3, TEMP

    ; update display and continue polling
    rcall update_LCD_display
    rjmp timer3_polling_loop

; **
; timer4:     Checks whether the top line content needs to be modifie every DELAY4 (0.5) seconds.
;
; Registers:  TEMP - Temporary working register
; 
; Modifies: - TOP_LINE_CONTENT 		
;           - CURRENT_CHARSET_INDEX 
;           - CURRENT_CHAR_INDEX
; 
; Stack:      None.
; Returns:	  Nothing.
;  
timer4:
	push TEMP
    in TEMP, SREG
    push TEMP

	rcall record_top_line_status

	pop TEMP
    out SREG, TEMP
    pop TEMP

	reti

; **
; update_LCD_display:  Writes the current state of the LCD display to the screen.
;
; Registers:           None.
; 
; Modifies:            None.
; Stack:               None.
; Returns:             Nothing.
;  
update_LCD_display:
	rcall lcd_clr ; Clear the screen
	rcall display_btn_status
	rcall display_btn_value
	rcall display_top_line_content

	ret

; **
; display_btn_status: Displays '*' on the bottom left of the LCD if a button is currently
;                            being pressed, or '-' otherwise.
;
; Registers:           TEMP  - Temporary working register
;                      TEMP2 - Second temporary register
; 
; Modifies:            None.
; Stack:               None.
; Returns:             Nothing.
;  
display_btn_status:
    push TEMP
	push TEMP2

	; Set cursor position
	ldi TEMP, 1
	ldi TEMP2, 15
	push TEMP
    push TEMP2
    rcall lcd_gotoxy
    pop TEMP2
    pop TEMP

    ; Get the btn value
	lds TEMP, BUTTON_IS_PRESSED
	cpi TEMP, 1
	breq btn_pressed
	ldi TEMP, '-'
	rjmp write_btn_status

  btn_pressed:
    ldi TEMP, '*'

  write_btn_status:
  	push TEMP
	rcall lcd_putchar
	pop TEMP

	pop TEMP2
	pop TEMP
	ret

; **
; display_btn_value:   Displays the most recent button press event to the LCD screen.
;                      Button values will appear at the bottom left of the screen and
;                      in the order: ['L', 'D', 'U', 'R']
;                      - 'L' = left  button
;                      - 'R' = right button
;                      - 'U' = Up button
;                      - 'D' = Down button
;
; Registers:           TEMP  - Temporary working register
;                      TEMP2 - Second temporary register
;                      r18   - Stores LAST_BUTTON_PRESSED value
; 
; Modifies:            None.
; Stack:               None.
; Returns:             Nothing.
;  
display_btn_value:
	push TEMP
	push TEMP2 ; column
	push r18

	; Determine the column to write the character to
	lds r18, LAST_BUTTON_PRESSED
	clr TEMP2
	cpi r18, 'L'
	breq set_cursor_position

	inc TEMP2
	cpi r18, 'D'
	breq set_cursor_position

	inc TEMP2
	cpi r18, 'U'
	breq set_cursor_position

	inc TEMP2
	cpi r18, 'R'
	breq set_cursor_position

  set_cursor_position:
    ldi TEMP, 1 ; Row 1
    push TEMP
    push TEMP2
    rcall lcd_gotoxy
    pop TEMP2
    pop TEMP

	; Write to the screen
	push r18
	rcall lcd_putchar
	pop r18

	pop r18
	pop TEMP2
	pop TEMP

	ret

; **
; display_top_line_content:  Displays the top line characters on the LCD screen
;
; Registers:           TEMP  - Temporary working register
;                      TEMP2 - Second temporary register
;                      ZH:ZL - Address of the TOP_LINE_CONTENT
; 
; Modifies:            None.
; Stack:               None.
; Returns:             Nothing.
;  
display_top_line_content:
	push TEMP
	push TEMP2
	push ZH
	push ZL

	ldi ZL, low(TOP_LINE_CONTENT)
	ldi ZH, high(TOP_LINE_CONTENT)

	clr TEMP ; counter / column
	clr ZERO
  write_top_loop:
    ; Set cursor position
	push ZERO
	push TEMP
    rcall lcd_gotoxy
    pop TEMP
    pop ZERO

	ld TEMP2, Z+

	; Write to the screen
	push TEMP2
	rcall lcd_putchar
	pop TEMP2

	inc TEMP
	cpi TEMP, LCD_COLUMN - 1
	brne write_top_loop

	pop ZL
	pop ZH
	pop TEMP2
	pop TEMP

	ret

; **
; timer1:     Checks whether a button has been pressed, and if so, which button it is.
;                   - Writes 1 (PRESSED) or 0 (NOT PRESSED) to BUTTON_IS_PRESSED
;                   - Writes 'L', 'R', 'U' or 'D' to LAST_BUTTON_PRESSED if pressed
;
; Registers:  TEMP  - Temporary working register
;             TEMP2 - Second temporary register
;             XH:XL - Stores the ADC button conversion
;             YH:YL - Stores the button thresholds
; 
; Modifies: - LAST_BUTTON_PRESSED.
;           - BUTTON_IS_PRESSED.
; 
; Stack:      None.
; Returns:	  Nothing.
;  
record_btn_status:
	push TEMP
	push TEMP2
	push XL
	push XH
	push YL
	push YH
	
	; Start ADC conversion
	lds	TEMP, ADCSRA	
	ori TEMP, 0x40 ; 0x40 = 0b01000000
	sts	ADCSRA, TEMP

	; Wait for it to complete, check for bit 6, the ADSC bit
  wait:
    lds TEMP, ADCSRA
	andi TEMP, 0x40
	brne wait

	; Read the value, use XH:XL to store the 10-bit result
	lds XL, ADCL
	lds XH, ADCH

	ldi TEMP2, 1

	; Determine which button was pressed
	ldi YL, low(BUTTON_RIGHT_ADC)
	ldi YH, high(BUTTON_RIGHT_ADC)
	ldi TEMP, 'R'
	cp XL, YL  
	cpc XH, YH 
	brlo save_btn_results

	ldi YL, low(BUTTON_UP_ADC)
	ldi YH, high(BUTTON_RIGHT_ADC)
	ldi TEMP, 'U'
	cp XL, YL  
	cpc XH, YH 
	brlo save_btn_results

	ldi YL, low(BUTTON_DOWN_ADC)
	ldi YH, high(BUTTON_DOWN_ADC)
	ldi TEMP, 'D'
	cp XL, YL  
	cpc XH, YH 
	brlo save_btn_results

	ldi YL, low(BUTTON_LEFT_ADC)
	ldi YH, high(BUTTON_LEFT_ADC)
	ldi TEMP, 'L'
	cp XL, YL  
	cpc XH, YH 
	brlo save_btn_results

	ldi YL, low(BUTTON_SELECT_ADC)
	ldi YH, high(BUTTON_SELECT_ADC)
	cp XL, YL  
	cpc XH, YH
	brlo skip

	; No buttons were pressed
	clr TEMP2
	rjmp skip
				
  save_btn_results:
    sts LAST_BUTTON_PRESSED, TEMP
  skip:
	sts BUTTON_IS_PRESSED, TEMP2

    pop YH
    pop YL
    pop XH
    pop XL
	pop TEMP2
    pop TEMP

    ret

; **
; Record_top_line_status: Checks if the user wants to modify the current character at their 
;                         cursor position, or modify the cursor position itself. Holding
;                         'U' or 'D' modifyies the character while holding 'L' or 'R' modifies
;                         the cursor position on the screen.
;
; Registers:  TEMP - Temporary working register
; 
; Modifies: - TOP_LINE_CONTENT 		
;           - CURRENT_CHARSET_INDEX 
;           - CURRENT_CHAR_INDEX
; 
; Stack:      None.
; Returns:	  Nothing.
;  
record_top_line_status:
	push TEMP

	lds TEMP, BUTTON_IS_PRESSED
	cpi TEMP, 1
	brne end

	rcall check_modify_char
	rcall check_modify_position

  end:
    pop TEMP

	reti

; **
; Record_top_line_status: Checks if the user wants to modify the current character at their 
;                         cursor position. 'U' increases the character, 'D' decreses the character.
;
; Registers:  TEMP - Temporary working register
;             TEMP2 - Second temporary register
;             r18   - Stores CURRENT_CHAR_INDEX
;             YH:YL - Tempory address
;             ZH:ZL - Temporary address
; 
; Modifies: - TOP_LINE_CONTENT 		
;           - CURRENT_CHARSET_INDEX 
; 
; Stack:      None.
; Returns:	  Nothing.
;  
check_modify_char:
	push TEMP
	push TEMP2
	push r18
	push YL
	push YH
	push ZL
	push ZH

	clr ZERO
	lds TEMP, LAST_BUTTON_PRESSED

	; Check if 'U' is being held
	cpi TEMP, 'U'
	brne check_for_down
		
		ldi YL, low(CURRENT_CHARSET_INDEX)
		ldi YH, high(CURRENT_CHARSET_INDEX)
		lds r18, CURRENT_CHAR_INDEX

        ; Store the value of the char index into TEMP
		add YL, r18
		adc YH, ZERO
		ld TEMP2, Y

		ldi ZL, low(AVAILABLE_CHARSET << 1)
		ldi ZH, high(AVAILABLE_CHARSET << 1)

        ; Store the value of the char into TEMP2
		add ZL, TEMP2
		adc ZH, ZERO
		lpm TEMP, Z

		; Check for the end of the string 
		tst TEMP
		breq end_modify_char

        ; Increment and save the index
        inc TEMP2
        st Y, TEMP2

		ldi ZL, low(TOP_LINE_CONTENT)
		ldi ZH, high(TOP_LINE_CONTENT)

        ; Save the new character to the LCD screen
		add ZL, r18
		adc ZH, ZERO
		st Z, TEMP

		rjmp end_modify_char
		
	; Check if 'D' is being held
	check_for_down:
	cpi TEMP, 'D'
	brne end_modify_char

		ldi YL, low(CURRENT_CHARSET_INDEX)
		ldi YH, high(CURRENT_CHARSET_INDEX)
		lds r18, CURRENT_CHAR_INDEX

        ; Store the value of the char index into TEMP
		add YL, r18
		adc YH, ZERO
		ld TEMP, Y

        ; Check for the beginning of the string
        tst TEMP
        breq end_modify_char
			
        ; Decrement and save the index
        dec TEMP
        st Y, TEMP

		ldi ZL, low(AVAILABLE_CHARSET << 1)
		ldi ZH, high(AVAILABLE_CHARSET << 1)

        ; Store the value of the char into TEMP2
		add ZL, TEMP
		adc ZH, ZERO
		lpm TEMP2, Z

		ldi ZL, low(TOP_LINE_CONTENT)
		ldi ZH, high(TOP_LINE_CONTENT)

        ; Save the new character to the LCD screen
        add ZL, r18
		adc ZH, ZERO
		st Z, TEMP2
		
  end_modify_char:
	pop ZH
	pop ZL
	pop YH
	pop YL
	pop r18
	pop TEMP2
    pop TEMP

	ret

; **
; Check_modfiy_position:  Checks if the user wants to modify the current cursor. 
;                         'R' moves the cursor to the right, while 'L' moves it left.
;
; Registers:  TEMP - Temporary working register
; 
; Modifies: - CURRENT_CHAR_INDEX
; 
; Stack:      None.
; Returns:	  Nothing.
;  
check_modify_position:
	push TEMP

	lds TEMP, LAST_BUTTON_PRESSED

	cpi TEMP, 'R'
	brne check_for_left
	lds TEMP, CURRENT_CHAR_INDEX
	
    ; Check for end of screen
	cpi TEMP, LCD_COLUMN - 1
	breq end_modify_position

	inc TEMP
	sts CURRENT_CHAR_INDEX, TEMP
	rjmp end_modify_position
  
  check_for_left:
    cpi TEMP, 'L'
	brne end_modify_position
	lds TEMP, CURRENT_CHAR_INDEX
	
    ; Check for start of the screen
	tst TEMP
	breq end_modify_position
    
	dec TEMP
	sts CURRENT_CHAR_INDEX, TEMP

  end_modify_position:
	pop TEMP

	ret

; r17:r16 -- word 1
; r19:r18 -- word 2
; word 1 < word 2? return -1 in r25
; word 1 > word 2? return 1 in r25
; word 1 == word 2? return 0 in r25
;
compare_words:
	; if high bytes are different, look at lower bytes
	cp r17, r19
	breq compare_words_lower_byte

	; since high bytes are different, use these to
	; determine result
	;
	; if C is set from previous cp, it means r17 < r19
	; 
	; preload r25 with 1 with the assume r17 > r19
	ldi r25, 1
	brcs compare_words_is_less_than
	rjmp compare_words_exit

compare_words_is_less_than:
	ldi r25, -1
	rjmp compare_words_exit

compare_words_lower_byte:
	clr r25
	cp r16, r18
	breq compare_words_exit

	ldi r25, 1
	brcs compare_words_is_less_than  ; re-use what we already wrote...

compare_words_exit:
	ret

; ****************************************************
; **************** END OF CODE ECTION ****************
; ****************************************************

; Program data

.cseg
AVAILABLE_CHARSET: .db "0123456789abcdef_", 0

.dseg

BUTTON_IS_PRESSED: .byte 1			; updated by timer1 interrupt, used by LCD update loop
LAST_BUTTON_PRESSED: .byte 1        ; updated by timer1 interrupt, used by LCD update loop

TOP_LINE_CONTENT: .byte 16			; updated by timer4 interrupt, used by LCD update loop
CURRENT_CHARSET_INDEX: .byte 16		; updated by timer4 interrupt, used by LCD update loop
CURRENT_CHAR_INDEX: .byte 1			; ; updated by timer4 interrupt, used by LCD update loop