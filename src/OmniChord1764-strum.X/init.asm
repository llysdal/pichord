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

    BANKSEL OPA1CON
    MOVLW   10010000b	; OPA1 enable, unity gain, override disabled
    MOVWF   OPA1CON
    MOVLW   00000010b	; OPA1+ is DAC1
    MOVWF   OPA1PCHS

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
    MOVLW   0x1F	; Timer 2 period register, 31.25kHz (with 1:8 prescale)
    MOVWF   T2PR
    MOVLW   00000000b  ; Free-running Period Pulse
    MOVWF   T2HLT

	BANKSEL T4TMR
    CLRF    T4TMR	; Clear timer
    MOVLW   00000100b	; Timer 4 LFINTOSC = 31.25KHz clock
    MOVWF   T4CLKCON
    MOVLW   00110000b	; Timer 4 off, 1:8 prescaler, 1:1 postscaler
    MOVWF   T4CON
    MOVLW   0x1F		; Timer 4 period register
    MOVWF   T4PR
    MOVLW   00000000b  ; Free-running Period Pulse
    MOVWF   T4HLT
    
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
    BSF	    PIE4, TMR4IE    ; Enable timer 4 interrupts (for decreasing volume)
    
;----------------- I/O
    BANKSEL TRISA	; Input/Output (1 is input, 0 is output)
    MOVLW   00001000b
    MOVWF   TRISA	; bit 3 has to be 1 (for reasons)
    MOVLW   00000011b	; SDA and SCL are inputs
    MOVWF   TRISC
    BANKSEL ANSELA	; Both ports are digital I/O
    CLRF    ANSELA
    CLRF    ANSELC

    BANKSEL PORTA	; And we'll clear them
    CLRF    PORTA
    CLRF    PORTC

;----------------- I2C
	BANKSEL	SSP1CON1
	MOVLW	00101000b	; Enable I2C serial port, I2C master mode
	MOVWF	SSP1CON1
	
	MOVLW	0x13		; Set I2C baud rate to be 400kHz
;	MOVLW	0x4F		; Set I2C baud rate to be 100kHz
	MOVWF	SSP1ADD

;----------------- Peripheral select
	BANKSEL	SSPCLKPPS
	MOVLW	10000b
	MOVWF	SSPCLKPPS	; RC0 is I2C SCL input

	BANKSEL	SSPDATPPS
	MOVLW	10001b
	MOVWF	SSPDATPPS	; RC1 is I2C SDA input

	BANKSEL	RC0PPS
	MOVLW	10010b
	MOVWF	RC0PPS		; RC0 is I2C SCL output

	BANKSEL	RC1PPS
	MOVLW	10011b
	MOVWF	RC1PPS		; RC1 is I2C SDA output
    
;----------------- Variables     
	BANKSEL	0
    CLRF    CHORD_CHANGE_OVERFLOW
    CLRF    CURRENT_CHORD_MODE
    CLRF    CURRENT_CHORD
    
	MOVLW	0
	MOVWF	STRUM1_1_VOL
	MOVWF	STRUM1_2_VOL
	MOVWF	STRUM1_3_VOL
	MOVWF	STRUM2_1_VOL
	MOVWF	STRUM2_2_VOL
	MOVWF	STRUM2_3_VOL
	MOVWF	STRUM3_1_VOL
	MOVWF	STRUM3_2_VOL
	MOVWF	STRUM3_3_VOL
	MOVWF	STRUM4_1_VOL
	MOVWF	STRUM4_2_VOL
	MOVWF	STRUM4_3_VOL
    
    MOVLW   #BUFF1_LO
    MOVWF   SAMPLE_POS
    
;----------------- MPR121 init config
	BANKSEL 0
	; Autoconfig reg 1
	; https://vscode.dev/github/adafruit/Adafruit_MPR121/blob/master/Adafruit_MPR121.cpp#L147
	MOVLW	0x7B
	MOVWF	I2C_REG
	MOVLW	00001011b
	MOVWF	I2C_DATA
	CALL	I2CWrite

	; Autoconfig MPR121_UPLIMIT
	MOVLW	0x7D	; MPR121_UPLIMIT
	MOVWF	I2C_REG
	MOVLW	200		; ((Vdd - 0.7)/Vdd) * 256
	MOVWF	I2C_DATA
	CALL	I2CWrite

	; Autoconfig MPR121_TARGETLIMIT
	MOVLW	0x7B	; MPR121_TARGETLIMIT
	MOVWF	I2C_REG
	MOVLW	180		; UPLIMIT * 0.9
	MOVWF	I2C_DATA
	CALL	I2CWrite

	; Autoconfig MPR121_LOWLIMIT
	MOVLW	0x7B	; MPR121_LOWLIMIT
	MOVWF	I2C_REG
	MOVLW	130		; UPLIMIT * 0.65
	MOVWF	I2C_DATA
	CALL	I2CWrite

	; Enable electrodes
	MOVLW	0x5E	; MPR121_ECR
	MOVWF	I2C_REG
	MOVLW	10000000b + 12	; enable all 12
	MOVWF	I2C_DATA
	CALL	I2CWrite

;----------------- Get ready for start 
    BANKSEL T1CON
    BSF	    T1CON, TMR1ON   ; Start timer 1
    BSF	    T2CON, TMR2ON   ; Start timer 2
	BANKSEL	T4CON
    BSF	    T4CON, TMR4ON   ; Start timer 4
    
    MOVLB   0	    ; Bank 0
