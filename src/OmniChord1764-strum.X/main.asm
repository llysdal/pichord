; ******************************************************************************
;  Omnichord
; ******************************************************************************

    INCLUDE	"p16f1764.inc"
    LIST	P=16F1764
    RADIX	DEC
    ERRORLEVEL	-302	; Surpress warnings about changing registers not in bank 0
    
    __CONFIG _CONFIG1, _FOSC_INTOSC & _WDTE_OFF & _PWRTE_OFF & _MCLRE_ON & _CP_OFF & _BOREN_OFF & _CLKOUTEN_OFF & _IESO_OFF & _FCMEN_OFF
    __CONFIG _CONFIG2, _WRT_OFF & _PPS1WAY_OFF & _ZCD_OFF & _PLLEN_ON & _STVREN_ON & _BORV_LO & _LPBOR_OFF & _LVP_ON

; +5v		VDD 1-|--U--|-14 VSS	Gnd
;			RA5 2-|		|-13 RA0	ICSPDAT
;			RA4 3-|	 1	|-12 RA1	ICSPCLK
; ~MCLR/Vpp	RA3 4-|  7	|-11 RA2	
;			RC5 5-|  6	|-10 RC0	SCL
;			RC4 6-|  4	|-9	 RC1	SDA
;			RC3 7-|_____|-8	 RC2	DAC1 out

;-------------------------------------------------------------------------------
;	MEMORY
;-------------------------------------------------------------------------------
; 0x500 - 0x5FF	    Other lookup tables
; 0x900 - 0xAB0	    Chords A to G#, with bits 7 and 8 determining mode
 
;-------------------------------------------------------------------------------
;	VARIABLES
;-------------------------------------------------------------------------------
; Sample Buffers
; 0xA0-0xEF (in bank 1)
    CBLOCK  0x0A0
	BUFF1_LO: 16	; 0xA0 0b10100000
	BUFF1_HI: 16	; 0xB0 0b10110000
	BUFF2_LO: 16	; 0xC0 0b11000000
	BUFF2_HI: 16	; 0xD0 0b11010000
    ENDC
	
; Bank 0 variables
; 0x20-0x6F (80)
    CBLOCK  0x020
	LOOP_VAR

	SAMPLE_POS
	SYS_FLAGS

	CHORD_CHANGE_OVERFLOW
	CURRENT_CHORD_MODE
	CURRENT_CHORD

	CURRENT_STRUM

	CHORD1_NOTE
	CHORD2_NOTE
	CHORD3_NOTE
	
	STRUM1_1_PHASE_LO
	STRUM1_2_PHASE_LO
	STRUM1_3_PHASE_LO
	STRUM2_1_PHASE_LO
	STRUM2_2_PHASE_LO
	STRUM2_3_PHASE_LO
	STRUM3_1_PHASE_LO
	STRUM3_2_PHASE_LO
	STRUM3_3_PHASE_LO
	STRUM4_1_PHASE_LO
	STRUM4_2_PHASE_LO
	STRUM4_3_PHASE_LO
;	STRUM1_1_PHASE_MID
;	STRUM1_2_PHASE_MID
;	STRUM1_3_PHASE_MID
;	STRUM2_1_PHASE_MID
;	STRUM2_2_PHASE_MID
;	STRUM2_3_PHASE_MID
;	STRUM3_1_PHASE_MID
;	STRUM3_2_PHASE_MID
;	STRUM3_3_PHASE_MID
;	STRUM4_1_PHASE_MID
;	STRUM4_2_PHASE_MID
;	STRUM4_3_PHASE_MID
	STRUM1_1_PHASE_HI
	STRUM1_2_PHASE_HI
	STRUM1_3_PHASE_HI
	STRUM2_1_PHASE_HI
	STRUM2_2_PHASE_HI
	STRUM2_3_PHASE_HI
	STRUM3_1_PHASE_HI
	STRUM3_2_PHASE_HI
	STRUM3_3_PHASE_HI
	STRUM4_1_PHASE_HI
	STRUM4_2_PHASE_HI
	STRUM4_3_PHASE_HI

	STRUM1_1_VOL
	STRUM1_2_VOL
	STRUM1_3_VOL
	STRUM2_1_VOL
	STRUM2_2_VOL
	STRUM2_3_VOL
	STRUM3_1_VOL
	STRUM3_2_VOL
	STRUM3_3_VOL
	STRUM4_1_VOL
	STRUM4_2_VOL
	STRUM4_3_VOL
    ENDC
    
; Common RAM variables
; 0x70-0x7F (16)
    CBLOCK  0x070
	TEMP
	TEMP2
	SAMPLE_LO
	SAMPLE_HI
	OUTPUT1_LO
	OUTPUT1_HI

	ELE_LO
	ELE_HI

	I2C_REG
	I2C_DATA
    ENDC
    
;-------------------------------------------------------------------------------
;	DEFINES
;-------------------------------------------------------------------------------
 
#define ZERO	STATUS, Z   ; Zero Flag
#define CARRY	STATUS, C   ; Carry
#define BORROW	STATUS, C   ; Borrow is the same as Carry 

#define TEST_PIN	PORTA, 2

#define SCL		PORTC, 0
#define SDA		PORTC, 1
#define I2C_SLAVE_ADDR_READ		(0x5A<<1) + 1
#define I2C_SLAVE_ADDR_WRITE	(0x5A<<1)

#define SAMPLES_REQ	SYS_FLAGS, 0	; New samples are required
#define I2C_REQ		SYS_FLAGS, 1	; We should read I2C data again
    
#define BUFFER_OVERFLOW	SAMPLE_POS, 4	; Have we run out of buffer?
#define BUFFER_ONE		SAMPLE_POS, 5	; Are we using buffer one?
    
#define CHORD_MODE_UPPER_BANK	CURRENT_CHORD_MODE, 2	; Are we in the upper chord mode bank?
	
;-------------------------------------------------------------------------------
;	ENTRY
;-------------------------------------------------------------------------------
	INCLUDE	"data.asm"

    ORG	    0x0000
    NOP
    GOTO    Init
      
;-------------------------------------------------------------------------------
;	INTERRUPT
;-------------------------------------------------------------------------------
    ORG	    0x0004	; Interrupt vector location
			; This is executed every 31.25kHz
			; W, STATUS, BSR, FSR and PCLATH are shadowed
InterruptEnter:
    MOVLB   0	    ; Bank 0
    BTFSC   PIR1, TMR1IF    ; If TMR1 interrupt,
		GOTO	StrumAdvance
	BTFSC	PIR4, TMR4IF	; If TMR4 interrupt,
		GOTO	DecreaseVolume
    BTFSS   PIR1, TMR2IF    ; Check if TMR2 interrupt
		GOTO    InterruptExit
    BCF	    PIR1, TMR2IF    ; Clear TMR2 interrupt flag
    
;----------------- Output buffer output
	CLRF    FSR0H			; Chord buffer
    MOVF    SAMPLE_POS, W	; Load sample index into FSR0
    MOVWF   FSR0L
    MOVIW   [FSR0]			; Fetch low byte of sample
    MOVWF   OUTPUT1_LO
    MOVIW   16[FSR0]		; Fetch high byte of sample
    MOVWF   OUTPUT1_HI
    
;----------------- Output buffer increment and switching
    INCF    SAMPLE_POS, F	; Move onto the next sample
    
    BTFSS   BUFFER_OVERFLOW	; Have we run out of samples in this buffer?
		GOTO    OutputSample	; If not, just output sample
    
    BCF	    BUFFER_OVERFLOW	; Reset overflow
    MOVLW   01100000b
    XORWF   SAMPLE_POS, F	; Switch buffer
    
    BSF	    SAMPLES_REQ		; Request more samples
   
;----------------- DAC output
OutputSample:
    BANKSEL DAC1REFL
    MOVF    OUTPUT1_LO, W	; Chord output
    MOVWF   DAC1REFL
    MOVF    OUTPUT1_HI, W
    MOVWF   DAC1REFH
    BSF	    DACLD, DAC1LD

    GOTO    InterruptExit
    
StrumAdvance:
    BCF	    PIR1, TMR1IF    ; Clear TMR1 interrupt flag

;----------------- I2C update strum
	CALL	I2CUpdateStrum

;----------------- Delay
    MOVLW   64
    ADDWF   CHORD_CHANGE_OVERFLOW, F
    BTFSS   CARRY
		GOTO    InterruptExit

	BSF		I2C_REQ
    
;----------------- Chord handling
    BTFSS   CHORD_MODE_UPPER_BANK
		MOVLW   HIGH CHORDS
    BTFSC   CHORD_MODE_UPPER_BANK
		MOVLW   HIGH UPPER_CHORDS	    
    MOVWF   FSR0H		    ; Get the correct chord bank
    
    MOVF    CURRENT_CHORD_MODE, W   ; Load current chord mode...
    MOVWF   TEMP
    LSLF    TEMP, F	    ; 0b1 -> 0b10
    LSLF    TEMP, F	    ; 0b10 -> 0b100
    LSLF    TEMP, F	    ; 0b100 -> 0b1000
    LSLF    TEMP, F	    ; 0b1000 -> 0b10000
    LSLF    TEMP, F	    ; 0b10000 -> 0b100000
    LSLF    TEMP, W	    ; 0b100000 -> 0b1000000
    ADDWF   CURRENT_CHORD, W; Load current chord...
    ADDWF   CURRENT_CHORD, W
    ADDWF   CURRENT_CHORD, W; Each chord has 3 notes, so multiply by 3
    MOVWF   FSR0L
    
	MOVIW   [FSR0]	    ; Load the notes..
    MOVIW   [FSR0]
    MOVWF   CHORD1_NOTE
    MOVIW   1[FSR0]
    MOVWF   CHORD2_NOTE
    MOVIW   2[FSR0]
    MOVWF   CHORD3_NOTE

;----------------- Sequence advancement
;	GOTO	InterruptExit

;	INCF	CURRENT_STRUM, F
;	MOVF	CURRENT_STRUM, W
;	SUBLW	12
;	BTFSS	ZERO
;		GOTO	StrumNoClear
;	CLRF	CURRENT_STRUM
;	GOTO	IncChordMode
StrumNoClear:
	GOTO	InterruptExit

;IncChordMode:
;	INCF    CURRENT_CHORD_MODE, F	; Increment current chord mode
;    MOVF    CURRENT_CHORD_MODE, W
;    SUBLW   7					; If current chord mode < 7
;    BTFSS   ZERO
;		GOTO    InterruptExit	; then Exit
;    CLRF    CURRENT_CHORD_MODE	; else, reset current chord mode
;    
;    INCF    CURRENT_CHORD, F	; Increment current chord
;    MOVF    CURRENT_CHORD, W
;    SUBLW   12					; If current chord < 12
;    BTFSS   ZERO
;		GOTO    InterruptExit   ; then Exit
;    CLRF    CURRENT_CHORD		; else, reset current chord
    
DecreaseVolume:
    BCF	    PIR4, TMR4IF    ; Clear TMR4 interrupt flag
	
	MOVF	STRUM1_1_VOL, W
	BTFSS	ZERO
		DECF	STRUM1_1_VOL, F
	MOVF	STRUM1_2_VOL, W
	BTFSS	ZERO
		DECF	STRUM1_2_VOL, F
	MOVF	STRUM1_3_VOL, W
	BTFSS	ZERO
		DECF	STRUM1_3_VOL, F

	MOVF	STRUM2_1_VOL, W
	BTFSS	ZERO
		DECF	STRUM2_1_VOL, F
	MOVF	STRUM2_2_VOL, W
	BTFSS	ZERO
		DECF	STRUM2_2_VOL, F
	MOVF	STRUM2_3_VOL, W
	BTFSS	ZERO
		DECF	STRUM2_3_VOL, F

	MOVF	STRUM3_1_VOL, W
	BTFSS	ZERO
		DECF	STRUM3_1_VOL, F
	MOVF	STRUM3_2_VOL, W
	BTFSS	ZERO
		DECF	STRUM3_2_VOL, F
	MOVF	STRUM3_3_VOL, W
	BTFSS	ZERO
		DECF	STRUM3_3_VOL, F

	MOVF	STRUM4_1_VOL, W
	BTFSS	ZERO
		DECF	STRUM4_1_VOL, F
	MOVF	STRUM4_2_VOL, W
	BTFSS	ZERO
		DECF	STRUM4_2_VOL, F
	MOVF	STRUM4_3_VOL, W
	BTFSS	ZERO
		DECF	STRUM4_3_VOL, F

	GOTO	InterruptExit

I2CUpdateStrum:
#define		STRUM_VOL	6
	BTFSC	ELE_LO, 0
		BSF	STRUM1_1_VOL, STRUM_VOL
	BTFSC	ELE_LO, 1
		BSF	STRUM1_1_VOL, STRUM_VOL
	BTFSC	ELE_LO, 2
		BSF	STRUM1_2_VOL, STRUM_VOL

	BTFSC	ELE_LO, 3
		BSF	STRUM2_1_VOL, STRUM_VOL
	BTFSC	ELE_LO, 4
		BSF	STRUM2_1_VOL, STRUM_VOL
	BTFSC	ELE_LO, 5
		BSF	STRUM2_2_VOL, STRUM_VOL

	BTFSC	ELE_LO, 6
		BSF	STRUM3_1_VOL, STRUM_VOL
	BTFSC	ELE_LO, 7
		BSF	STRUM3_1_VOL, STRUM_VOL
	BTFSC	ELE_HI, 0
		BSF	STRUM3_2_VOL, STRUM_VOL

	BTFSC	ELE_HI, 1
		BSF	STRUM4_1_VOL, STRUM_VOL
	BTFSC	ELE_HI, 2
		BSF	STRUM4_1_VOL, STRUM_VOL
	BTFSC	ELE_HI, 3
		BSF	STRUM4_2_VOL, STRUM_VOL

	RETURN

UpdateStrum:
	MOVF	CURRENT_STRUM, W
	SUBLW	0
	BTFSC	ZERO
		BSF	STRUM1_1_VOL, 7
	MOVF	CURRENT_STRUM, W
	SUBLW	1
	BTFSC	ZERO
		BSF	STRUM1_2_VOL, 7
	MOVF	CURRENT_STRUM, W
	SUBLW	2
	BTFSC	ZERO
		BSF	STRUM1_3_VOL, 7
	MOVF	CURRENT_STRUM, W
	SUBLW	3
	BTFSC	ZERO
		BSF	STRUM2_1_VOL, 7
	MOVF	CURRENT_STRUM, W
	SUBLW	4
	BTFSC	ZERO
		BSF	STRUM2_2_VOL, 7
	MOVF	CURRENT_STRUM, W
	SUBLW	5
	BTFSC	ZERO
		BSF	STRUM2_3_VOL, 7
	MOVF	CURRENT_STRUM, W
	SUBLW	6
	BTFSC	ZERO
		BSF	STRUM3_1_VOL, 7
	MOVF	CURRENT_STRUM, W
	SUBLW	7
	BTFSC	ZERO
		BSF	STRUM3_2_VOL, 7
	MOVF	CURRENT_STRUM, W
	SUBLW	8
	BTFSC	ZERO
		BSF	STRUM3_3_VOL, 7
	MOVF	CURRENT_STRUM, W
	SUBLW	9
	BTFSC	ZERO
		BSF	STRUM4_1_VOL, 7
	MOVF	CURRENT_STRUM, W
	SUBLW	10
	BTFSC	ZERO
		BSF	STRUM4_2_VOL, 7
	MOVF	CURRENT_STRUM, W
	SUBLW	11
	BTFSC	ZERO
		BSF	STRUM4_3_VOL, 7
	RETURN

InterruptExit:
    RETFIE

;-------------------------------------------------------------------------------
;	SETUP
;-------------------------------------------------------------------------------
Init:
	INCLUDE	"init.asm"
    GOTO    Main
    
;-------------------------------------------------------------------------------
;	SAMPLE GEN
;-------------------------------------------------------------------------------
SampleGeneration:
	BSF		TEST_PIN

    MOVLW   #BUFF2_LO  ; Assume buffer 2
    BTFSS   BUFFER_ONE
		MOVLW   #BUFF1_LO  ; But use buffer 1 if else
    MOVWF   FSR1L
    CLRF    FSR1H
    
;----------------- Strum Sample Generation  
    MOVLW   16		; Setup loop that generates 16 strum samples
    MOVWF   LOOP_VAR
GenerateStrumSample:
	CLRF	SAMPLE_LO
	CLRF	SAMPLE_HI
	
	MOVLW	HIGH NOTE_TO_PHASE_ACC	; Setup FSR0 to read from note_to_phase_acc
	MOVWF	FSR0H

	MOVF	CHORD1_NOTE, W		; Load in the note
	ADDWF	CHORD1_NOTE, W		; Mult by 2 as phase accumulators are 16 bit
	MOVWF	FSR0L
	MOVIW	-24[FSR0]			; Do phase accumulator addition
	ADDWF   STRUM1_1_PHASE_LO, F
	MOVIW	-23[FSR0]
	ADDWFC  STRUM1_1_PHASE_HI, F
	MOVIW	0[FSR0]
	ADDWF   STRUM2_1_PHASE_LO, F
	MOVIW	1[FSR0]
	ADDWFC  STRUM2_1_PHASE_HI, F
	MOVIW	24[FSR0]
	ADDWF   STRUM3_1_PHASE_LO, F
	MOVIW	25[FSR0]
	ADDWFC  STRUM3_1_PHASE_HI, F
	MOVLW	24
	ADDWF	FSR0L, F
	MOVIW	24[FSR0]
	ADDWF   STRUM4_1_PHASE_LO, F
	MOVIW	25[FSR0]
	ADDWFC  STRUM4_1_PHASE_HI, F

	MOVF	CHORD2_NOTE, W		; Load in the note
	ADDWF	CHORD2_NOTE, W		; Mult by 2 as phase accumulators are 16 bit
	MOVWF	FSR0L
	MOVIW	-24[FSR0]			; Do phase accumulator addition
	ADDWF   STRUM1_2_PHASE_LO, F
	MOVIW	-23[FSR0]
	ADDWFC  STRUM1_2_PHASE_HI, F
	MOVIW	0[FSR0]
	ADDWF   STRUM2_2_PHASE_LO, F
	MOVIW	1[FSR0]
	ADDWFC  STRUM2_2_PHASE_HI, F
	MOVIW	24[FSR0]
	ADDWF   STRUM3_2_PHASE_LO, F
	MOVIW	25[FSR0]
	ADDWFC  STRUM3_2_PHASE_HI, F
	MOVLW	24
	ADDWF	FSR0L, F
	MOVIW	24[FSR0]
	ADDWF   STRUM4_2_PHASE_LO, F
	MOVIW	25[FSR0]
	ADDWFC  STRUM4_2_PHASE_HI, F

	MOVF	CHORD3_NOTE, W		; Load in the note
	ADDWF	CHORD3_NOTE, W		; Mult by 2 as phase accumulators are 16 bit
	MOVWF	FSR0L
	MOVIW	-24[FSR0]			; Do phase accumulator addition
	ADDWF   STRUM1_3_PHASE_LO, F
	MOVIW	-23[FSR0]
	ADDWFC  STRUM1_3_PHASE_HI, F
	MOVIW	0[FSR0]
	ADDWF   STRUM2_3_PHASE_LO, F
	MOVIW	1[FSR0]
	ADDWFC  STRUM2_3_PHASE_HI, F
	MOVIW	24[FSR0]
	ADDWF   STRUM3_3_PHASE_LO, F
	MOVIW	25[FSR0]
	ADDWFC  STRUM3_3_PHASE_HI, F
	MOVLW	24
	ADDWF	FSR0L, F
	MOVIW	24[FSR0]
	ADDWF   STRUM4_3_PHASE_LO, F
	MOVIW	25[FSR0]
	ADDWFC  STRUM4_3_PHASE_HI, F

	BCF		CARRY

	MOVF	STRUM1_1_VOL, W
	BTFSC	STRUM1_1_PHASE_HI, 7
		ADDWF	SAMPLE_LO, F
	MOVF	STRUM2_1_VOL, W
	BTFSC	STRUM2_1_PHASE_HI, 7
		ADDWF	SAMPLE_LO, F
	MOVF	STRUM3_1_VOL, W
	BTFSC	STRUM3_1_PHASE_HI, 7
		ADDWF	SAMPLE_LO, F
	MOVF	STRUM4_1_VOL, W
	BCF		CARRY
	BTFSC	STRUM4_1_PHASE_HI, 7
		ADDWF	SAMPLE_LO, F
	BTFSC	CARRY
		INCF	SAMPLE_HI, F

	MOVF	STRUM1_2_VOL, W
	BCF		CARRY
	BTFSC	STRUM1_2_PHASE_HI, 7
		ADDWF	SAMPLE_LO, F
	BTFSC	CARRY
		INCF	SAMPLE_HI, F
	MOVF	STRUM2_2_VOL, W
	BCF		CARRY
	BTFSC	STRUM2_2_PHASE_HI, 7
		ADDWF	SAMPLE_LO, F
	BTFSC	CARRY
		INCF	SAMPLE_HI, F
	MOVF	STRUM3_2_VOL, W
	BCF		CARRY
	BTFSC	STRUM3_2_PHASE_HI, 7
		ADDWF	SAMPLE_LO, F
	BTFSC	CARRY
		INCF	SAMPLE_HI, F
	MOVF	STRUM4_2_VOL, W
	BCF		CARRY
	BTFSC	STRUM4_2_PHASE_HI, 7
		ADDWF	SAMPLE_LO, F
	BTFSC	CARRY
		INCF	SAMPLE_HI, F

	MOVF	STRUM1_3_VOL, W
	BCF		CARRY
	BTFSC	STRUM1_3_PHASE_HI, 7
		ADDWF	SAMPLE_LO, F
	BTFSC	CARRY
		INCF	SAMPLE_HI, F
	MOVF	STRUM2_3_VOL, W
	BCF		CARRY
	BTFSC	STRUM2_3_PHASE_HI, 7
		ADDWF	SAMPLE_LO, F
	BTFSC	CARRY
		INCF	SAMPLE_HI, F
	MOVF	STRUM3_3_VOL, W
	BCF		CARRY
	BTFSC	STRUM3_3_PHASE_HI, 7
		ADDWF	SAMPLE_LO, F
	BTFSC	CARRY
		INCF	SAMPLE_HI, F
	MOVF	STRUM4_3_VOL, W
	BCF		CARRY
	BTFSC	STRUM4_3_PHASE_HI, 7
		ADDWF	SAMPLE_LO, F
	BTFSC	CARRY
		INCF	SAMPLE_HI, F

	
	MOVF    SAMPLE_LO, W	    ; Save sample output to buffer
	MOVWI	[FSR1]
	MOVF	SAMPLE_HI, W
	MOVWI	16[FSR1]
	INCF    FSR1L, F

	DECFSZ  LOOP_VAR, F	    ; Onto the next sample,,
	    GOTO    GenerateStrumSample

;----------------- Fulfillment
    BCF	    SAMPLES_REQ	    ; We've fulfilled the request for more samples
    
	BCF		TEST_PIN

    RETURN
    
;-------------------------------------------------------------------------------
;	I2C
;-------------------------------------------------------------------------------
I2CWaitUntilIdle:
	MOVLW	00011111b		;  SEN, RSEN, PEN, RCEN and ACKEN
	ANDWF	SSP1CON2, W		
	BTFSS	ZERO
		GOTO	I2CWaitUntilIdle
	BTFSC	SSP1STAT, R_NOT_W
		GOTO	$-1

	RETURN

; Reads 0x00 and 0x01 into EKE_LO and ELE_HI
I2CRead:
	BANKSEL	0
;	BSF		TEST_PIN

	BANKSEL	SSP1BUF
	CALL	I2CWaitUntilIdle

	BSF		SSP1CON2, SEN	; Initiate start condition
	CALL	I2CWaitUntilIdle

	MOVLW	I2C_SLAVE_ADDR_WRITE; Load I2C slave address
	MOVWF	SSP1BUF				; Transmission starts here
	CALL	I2CWaitUntilIdle
	BTFSC	SSP1CON2, ACKSTAT
		GOTO I2CReadNoAck		; No ACK, let's give up

;	MOVLW	0x00				; Touch statis register (0 - 7)
	MOVLW	0x00
	MOVWF	SSP1BUF
	CALL	I2CWaitUntilIdle
	BTFSC	SSP1CON2, ACKSTAT
		GOTO I2CReadNoAck		; No ACK, let's give up

	BSF		SSP1CON2, RSEN	; Initiate repeated start condition
	CALL	I2CWaitUntilIdle

	MOVLW	I2C_SLAVE_ADDR_READ ; Load I2C slave address
	MOVWF	SSP1BUF				; Transmission starts here
	CALL	I2CWaitUntilIdle
	BTFSC	SSP1CON2, ACKSTAT
		GOTO I2CReadNoAck		; No ACK, let's give up
	
	BSF		SSP1CON2, RCEN		; Configure as receiver
	BTFSS	SSP1STAT, BF		; Wait until we've receieved
		GOTO	$-1
	
	MOVF	SSP1BUF, W		; Read the data
	MOVWF	ELE_LO
	BCF		SSP1STAT, BF	; Signify we've read the data

	BCF		SSP1CON2, ACKDT	; Awknowledge
	BSF		SSP1CON2, ACKEN
	CALL	I2CWaitUntilIdle

	BSF		SSP1CON2, RCEN		; Configure as receiver
	BTFSS	SSP1STAT, BF		; Wait until we've receieved
		GOTO	$-1

	MOVF	SSP1BUF, W		; Read the data
	MOVWF	ELE_HI
	BCF		SSP1STAT, BF	; Signify we've read the data

;	; we actually want one more message here, but lets just stop for now

	BSF		SSP1CON2, ACKDT	; No awknowledge
	BSF		SSP1CON2, ACKEN

I2CReadNoAck:
	BANKSEL	0
;	BCF		TEST_PIN

	BCF		I2C_REQ		; and we're done!
	RETURN		

; Writes I2C_DATA to I2C_REG
I2CWrite:
	BANKSEL	SSP1BUF
	CALL	I2CWaitUntilIdle

	BSF		SSP1CON2, SEN	; Initiate start condition
	CALL	I2CWaitUntilIdle

	MOVLW	I2C_SLAVE_ADDR_WRITE; Load I2C slave address
	MOVWF	SSP1BUF				; Transmission starts here
	CALL	I2CWaitUntilIdle
	BTFSC	SSP1CON2, ACKSTAT
		GOTO I2CReadNoAck		; No ACK, let's give up

;	MOVLW	0x00				; Touch statis register (0 - 7)
	MOVF	I2C_REG, W
	MOVWF	SSP1BUF
	CALL	I2CWaitUntilIdle
	BTFSC	SSP1CON2, ACKSTAT
		GOTO I2CReadNoAck		; No ACK, let's give up

	MOVF	I2C_DATA, W
	MOVWF	SSP1BUF
	CALL	I2CWaitUntilIdle
	BTFSC	SSP1CON2, ACKSTAT
		GOTO I2CReadNoAck		; No ACK, let's give up

	BSF		SSP1CON2, PEN

I2CWriteNoAck:
	BANKSEL	0
	RETURN		


;-------------------------------------------------------------------------------
;	RUNTIME
;-------------------------------------------------------------------------------
Main:
    BTFSC   SAMPLES_REQ
		CALL    SampleGeneration    ; If we require more samples, let's generate some!

	BTFSC	I2C_REQ
		CALL	I2CRead

    GOTO    Main
    
    END	    ; We should never reach here