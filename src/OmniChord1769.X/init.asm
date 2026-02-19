;----------------- Oscillator
    BANKSEL OSCCON
    MOVLW   11110000b ; Clockspeed 32MHz using 4xPLL, so 8Mips
;    MOVLW   01010000b    ; Clockspeed slow
    MOVWF   OSCCON
    MOVLW   00000000b	; No tuning
    MOVWF   OSCTUNE	
    
;----------------- ADC
    BANKSEL ADCON1
    MOVLW   00100000b	; Fosc/32 (required for 32MHz), and VSS/VDD used
    MOVWF   ADCON1	

;----------------- DAC
    BANKSEL DAC1CON0
    MOVLW   10000000b	; DAC1 enable, right justified, NO output on RA0, VSS/VDD
;    MOVLW   00000000b	; DAC1 disable, right justified
    MOVWF   DAC1CON0
    BANKSEL DAC2CON0
    MOVLW   10000000b	; DAC2 enable, right justified, NO output on RA0, VSS/VDD
    MOVWF   DAC2CON0
    
    BANKSEL OPA1CON
    MOVLW   10010000b	; OPA1 enable, unity gain, override disabled
    MOVWF   OPA1CON
    MOVLW   00000010b	; OPA1+ is DAC1
    MOVWF   OPA1PCHS

	MOVLW   10010000b	; OPA2 enable, unity gain, override disabled
    MOVWF   OPA2CON
    MOVLW   00000011b	; OPA2+ is DAC2
    MOVWF   OPA2PCHS
    
;----------------- Timers
    BANKSEL T1CON
    CLRF    TMR1L
    CLRF    TMR1H	; Clear timer
;    MOVLW   01000000b	; Timer 1 Fosc, 1:1 prescale = 32MHz, timer disable
    MOVLW   01100000b	; Timer 1 Fosc, 1:2 prescale = 8MHz, timer disable
    MOVWF   T1CON
    BCF	    T1GCON, GE	; Disabled gate
    
    BANKSEL T2TMR
    CLRF    T2TMR	; Clear timer
    MOVLW   00000001b	; Timer 2 Fosc/4 = 8MHz clock
    MOVWF   T2CLKCON
    MOVLW   00110000b	; Timer 2 off, 1:8 prescaler, 1:1 postscaler
;    MOVLW   00100000b	; Timer 2 off, 1:4 prescaler, 1:1 postscaler
    MOVWF   T2CON
    MOVLW   0x1F		; Timer 2 period register, 31.25kHz (with 1:8 prescale)
    MOVWF   T2PR
    MOVLW   00000000b  ; Free-running Period Pulse
    MOVWF   T2HLT
    
;----------------- Interrupts
    BSF	    INTCON, GIE	    ; Enable interrupts
    BSF	    INTCON, PEIE    ; Enable peripheral interrupts
    BANKSEL PIE1
    CLRF    PIE1
    CLRF    PIE2
    CLRF    PIE3
    CLRF    PIE4
    BSF	    PIE1, TMR2IE    ; Enable the output sample rate interrupt
    BSF	    PIE1, TMR1IE    ; Enable timer 1 interrupts
    
;----------------- I/O
    BANKSEL TRISA	; Input/Output (1 is input, 0 is output)
    MOVLW   00001000b
    MOVWF   TRISA	; bit 3 has to be 1 (for reasons)
    MOVLW   00000000b
    MOVWF   TRISB
    MOVLW   01000000b	; For keyboard scanning
;	MOVLW	00000000b
    MOVWF   TRISC

    BANKSEL ANSELA	; Ports are digital I/O
    CLRF    ANSELA
	CLRF	ANSELB
    CLRF    ANSELC
    
    BANKSEL PORTA	; And we'll clear them
    CLRF    PORTA
	CLRF	PORTB
    CLRF    PORTC

;	BSF		N_LD
    
;----------------- Variables
	BSF		RHYTHM_PLAY		; Turn on rhythm playing
	BCF		MEMORY_MODE		; Turn off continous chord playing
	BCF		AUTO_BASS		; Turn off auto bass

	MOVLW	0
	MOVWF	CURRENT_SEQ
	MOVLW	32
	MOVWF	SEQUENCE_SPEED
	CLRF    SEQUENCE_OVERFLOW

    CLRF    RHYTHM_SEQ_PTR

	MOVLW	0
	MOVWF	CURRENT_CHORD
	MOVLW	0
	MOVWF	CURRENT_CHORD_MODE
    
    MOVLW   #CHORD_BUFF1_LO
    MOVWF   SAMPLE_POS
    
;----------------- Get ready for start 
    BANKSEL T1CON
    BSF	    T1CON, TMR1ON   ; Start timer 1
    BSF	    T2CON, TMR2ON   ; Start timer 2
    
    MOVLB   0	    ; Bank 0