; ******************************************************************************
;  Omnichord
; ******************************************************************************

    INCLUDE	"p16f1769.inc"
    LIST	P=16F1769
    RADIX	DEC
    ERRORLEVEL	-302	; Surpress warnings about changing registers not in bank 0
    
    __CONFIG _CONFIG1, _FOSC_INTOSC & _WDTE_OFF & _PWRTE_OFF & _MCLRE_ON & _CP_OFF & _BOREN_OFF & _CLKOUTEN_OFF & _IESO_OFF & _FCMEN_OFF
    __CONFIG _CONFIG2, _WRT_OFF & _PPS1WAY_OFF & _ZCD_OFF & _PLLEN_ON & _STVREN_ON & _BORV_LO & _LPBOR_OFF & _LVP_ON

; +5v		VDD	 1-|--U--|-20 VSS	Gnd
; MX3		RA5	 2-|	 |-19 RA0
; MX2		RA4	 3-|  1	 |-18 RA1
; ~MCLR/Vpp	RA3	 4-|  6	 |-17 RA2
; MX1		RC5	 5-|  F	 |-16 RC0
; SER_RCLK	RC4	 6-|  1	 |-15 RC1
; DAC3 out	RC3	 7-|  7	 |-14 RC2	DAC1 out
; SER_DAT	RC6	 8-|  6	 |-13 RB4
; SER_CLK	RC7	 9-|  9	 |-12 RB5
; SER_LD	RB7 10-|_____|-11 RB6


; Parallel load shift register (for scanning keymatrix)
; Inputs:  SER_CLK, SER_LD, MX1, MX2, MX3
; Outputs: SER_DAT_I

; Shift register (for outputting triggers)
; Inputs:  SER_DAT_O, SER_CLK, SER_RCLK
; Outputs: CH, BS, x, CL, CY, HH, SD, BD

;-------------------------------------------------------------------------------
;	MEMORY
;-------------------------------------------------------------------------------
; 0x0500 - 0x05FF	    General lookup tables
; 0x1600 - 0x16FF	    Bass sequences  (xSSSOOOO) selection and offset bits
; 0x1700 - 0x18FF	    Drum sequences  (CH, BS, x, CL, CY, HH, SD, BD)
; 0x1900 - 0x1AB0	    Chords A to G#, with bits 7 and 8 determining mode
; 0x1B00 - 0x1DFF	    Wave lookup tables
 
;-------------------------------------------------------------------------------
;	VARIABLES
;-------------------------------------------------------------------------------
; Chord Sample Buffers
; 0xA0-0xEF (in bank 1)
    CBLOCK  0x0A0
	CHORD_BUFF1_LO: 16
	CHORD_BUFF1_HI: 16
	CHORD_BUFF2_LO: 16
	CHORD_BUFF2_HI: 16
    ENDC
; Bass Sample Buffers
; 0x1A0-0x1EF (in bank 3)
    CBLOCK  0x1A0
	BASS_BUFF1: 16
	EMPTY:		16
	BASS_BUFF2: 16
    ENDC
; Keystates
; 0x120-0x16F (in bank 2)
	CBLOCK	0x120
	KEYS:		12
	ENDC
	
; Bank 0 variables
; 0x20-0x6F (80)
    CBLOCK  0x020
	ILOOP_VAR
	LOOP_VAR

	ITEMP

	SAMPLE_POS
	SYS_FLAGS

	KEYREQ_OVERFLOW

	CURRENT_CHORD_MODE
	CURRENT_CHORD

	CURRENT_SEQ
	SEQUENCE_SPEED
	SEQUENCE_OVERFLOW
	
	RHYTHM_SEQ_PTR
	RHYTHM_SEQ_VAL
	
	BASS_NOTE
	BASS_SEQ_PTR
	BASS_SEQ_VAL
	
	BASS_PHASE_LO
	BASS_PHASE_MID
	BASS_PHASE_HI

	CHORDB_NOTE
	CHORD1_NOTE
	CHORD2_NOTE
	CHORD3_NOTE
	
	CHORDB_PHASE_LO
	CHORD1_PHASE_LO
	CHORD2_PHASE_LO
	CHORD3_PHASE_LO
	CHORDB_PHASE_MID
	CHORD1_PHASE_MID
	CHORD2_PHASE_MID
	CHORD3_PHASE_MID
	CHORDB_PHASE_HI
	CHORD1_PHASE_HI
	CHORD2_PHASE_HI
	CHORD3_PHASE_HI
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
	OUTPUT2
    ENDC
    
;-------------------------------------------------------------------------------
;	DEFINES
;-------------------------------------------------------------------------------
    
#define CHORD_WAVE	PULSE_WAVE_LOOKUP
#define	BASS_WAVE	OCT_SQUARE_WAVE_LOOKUP

#define ZERO	STATUS, Z   ; Zero Flag
#define CARRY	STATUS, C   ; Carry
#define BORROW	STATUS, C   ; Borrow is the same as Carry 

#define SAMPLES_REQ		SYS_FLAGS, 0	; New samples are required
#define KEYSCAN_REQ		SYS_FLAGS, 1	; New keyscan is required
#define TRIGGER_REQ		SYS_FLAGS, 2	; Need to output triggers
#define RHYTHM_PLAY		SYS_FLAGS, 3	; Are we playing a rhythm?
#define AUTO_BASS		SYS_FLAGS, 4	; Is auto bass on?
#define MEMORY_MODE		SYS_FLAGS, 5	; Should we keep playing chords after not pressing the button?
#define CHORD_PRESSED	SYS_FLAGS, 6	; Is a chord button currently pressed?
    
#define BUFFER_OVERFLOW	SAMPLE_POS, 4	; Have we run out of buffer?
#define BUFFER_ONE		SAMPLE_POS, 5	; Are we using buffer one?
    
#define CHORD_MODE_UPPER_BANK	CURRENT_CHORD_MODE, 2	; Are we in the upper chord mode bank?
    
#define TEST_PIN	PORTC, 0
    
#define	BD		RHYTHM_SEQ_VAL, 0
#define	SD		RHYTHM_SEQ_VAL, 1
#define	HH		RHYTHM_SEQ_VAL, 2
#define	CY		RHYTHM_SEQ_VAL, 3
#define	CL		RHYTHM_SEQ_VAL, 4
#define	BS		RHYTHM_SEQ_VAL, 6
#define	CH		RHYTHM_SEQ_VAL, 7

#define B_R		00010000b	; We use these to designate what the bass should use as root note
#define B_3		00100000b
#define B_5		01000000b
#define BASS_USING_ROOT	BASS_SEQ_VAL, 4
#define BASS_USING_3RD	BASS_SEQ_VAL, 5
#define BASS_USING_5TH	BASS_SEQ_VAL, 6
    

#define C1	PORTC, 5
#define C2	PORTA, 4
#define C3	PORTA, 5

#define SER_RCLK	PORTC, 4
#define SER_DAT_I	PORTC, 6
#define SER_CLK		PORTC, 7
#define SER_LD		PORTB, 7
#define SER_DAT_O	PORTB, 7
	
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
		GOTO	ChordSelect
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

	INCF	FSR0H, F		; Bass buffer
    MOVIW   [FSR0]			; Fetch low byte of sample
    MOVWF   OUTPUT2
	CLRF	FSR0H
    
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

	MOVF    OUTPUT2, W		; Bass output
    MOVWF   DAC2REFL
    CLRF	DAC2REFH
	LSLF	DAC2REFL, F
	RLF		DAC2REFH, F
	LSLF	DAC2REFL, F
	RLF		DAC2REFH, F
    BSF	    DACLD, DAC2LD

    GOTO    InterruptExit
    
ChordSelect:
	BCF		PIR1, TMR1IF	; Clear TMR1 inerrupt flag
	BCF		CHORD_PRESSED	; Assume no chord is pressed
	MOVLW	HIGH KEYS
	MOVWF	FSR0H
	MOVLW	LOW KEYS
	MOVWF	FSR0L

	MOVLW   12		; Setup loop that scans 12 keys
    MOVWF   ILOOP_VAR
ChordSelectLoop:
	MOVIW	FSR0++
	BTFSS	ZERO
		GOTO	ChordSelectOutput
	DECFSZ	ILOOP_VAR, F
		GOTO	ChordSelectLoop
	GOTO	OutputChord

ChordSelectOutput:
	ADDLW	256-1
	MOVWF	CURRENT_CHORD_MODE
	DECF	ILOOP_VAR, F
	MOVF	ILOOP_VAR, W
	MOVWF	CURRENT_CHORD
	BSF		CHORD_PRESSED	; We are pressing a chord!

	GOTO	OutputChord

ChordAdvance:
    BCF	    PIR1, TMR1IF    ; Clear TMR1 interrupt flag
    
;----------------- Delay
	MOVF	SEQUENCE_SPEED, W
    ADDWF   SEQUENCE_OVERFLOW, F
    BTFSS   CARRY
		GOTO    InterruptExit
    
;----------------- Chord handling
OutputChord:
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
	ADDLW	256-12
    MOVWF   CHORDB_NOTE
    MOVIW   [FSR0]
    MOVWF   CHORD1_NOTE
    MOVIW   1[FSR0]
    MOVWF   CHORD2_NOTE
    MOVIW   2[FSR0]
    MOVWF   CHORD3_NOTE

;	GOTO	InterruptExit

;----------------- Bass handling
    MOVLW   HIGH BASS_SEQUENCES
    MOVWF   FSR0H	    ; Begin to load bass sequences
    MOVF    BASS_SEQ_PTR, W
    MOVWF   FSR0L	    ; Find current bass note
    MOVIW   [FSR0]
    MOVWF   BASS_SEQ_VAL    ; Figure out which part of the chord we're basing on
    ANDLW   00001111b	    ; Remove the selection bits
    ADDLW   256-12	    ; Subtract 24
    BTFSC   BASS_USING_ROOT
		ADDWF   CHORD1_NOTE, W
    BTFSC   BASS_USING_3RD
		ADDWF   CHORD2_NOTE, W
    BTFSC   BASS_USING_5TH
		ADDWF   CHORD3_NOTE, W
    MOVWF   BASS_NOTE	    ; Save to bass note
    
;----------------- Rhythm Handling Delay (we only want to handle rhythm when it progresses)
	MOVF	SEQUENCE_SPEED, W
    ADDWF   SEQUENCE_OVERFLOW, F
    BTFSS   CARRY
		GOTO    InterruptExit

;----------------- Rhythm Handling
	BTFSS	RHYTHM_PLAY		; If we aren't playing a rhythm, skip this part
		GOTO	NoRhythm

	MOVLW	HIGH SEQUENCE_STARTS
	MOVWF	FSR0H
	MOVLW	LOW	SEQUENCE_STARTS
	ADDWF	CURRENT_SEQ, W
	MOVWF	FSR0L			; Find rhythm starting point
	MOVIW	[FSR0]
	MOVWF	ITEMP			; ITEMP = starting point

	MOVLW   HIGH RHYTHM_SEQUENCES	; Assume bank 1
    MOVWF   FSR0H			
	BTFSC	CURRENT_SEQ, 3		; If rhythm sequence > 8
		INCF	FSR0H			; Bank 2 instead
    LSRF	RHYTHM_SEQ_PTR, W	; Load rhythm sequence pointer with lower bit in carry
	CLRF	RHYTHM_SEQ_VAL
	BTFSC	CARRY				; If rhythm sequence pointer is odd,
		GOTO	RhythmCheckAutoBass	; Rhythm sequence val is actually empty (to get space between gates)

	ADDWF	ITEMP, W		; Add starting point of current sequence
    MOVWF   FSR0L
    MOVIW   [FSR0]
    MOVWF   RHYTHM_SEQ_VAL	; Fetch current rhythm sequence value (CH, BD, x, CL, CY, HH, SD, BD)


RhythmCheckAutoBass:
	BTFSC	AUTO_BASS		; If auto bass is on, keep current triggers
		GOTO	RhythmSetTrig
	MOVLW	11000000b
	IORWF	RHYTHM_SEQ_VAL	; If auto bass is off, turn on chord and bass triggers
	BTFSC	MEMORY_MODE			; Are we in memory mode?
		GOTO	RhythmSetTrig
	MOVLW	00111111b
	BTFSS	CHORD_PRESSED		; Are we pressing a chord?
		ANDWF	RHYTHM_SEQ_VAL	; If not, turn off the chord and bass triggers
	
RhythmSetTrig:
	BSF		TRIGGER_REQ
    
;----------------- Sequence advancement
AdvanceSequence:
    INCF    RHYTHM_SEQ_PTR  ; Increment rhythm sequence pointer
;    BTFSC   RHYTHM_SEQ_PTR, 0	; If current rhythm sequence pointer is odd
;	GOTO    InterruptExit   ; then Exit

	MOVLW   HIGH SEQUENCE_LENGTHS	; Find sequence length
    MOVWF   FSR0H
	MOVLW	LOW	SEQUENCE_LENGTHS
	ADDWF	CURRENT_SEQ, W
	MOVWF	FSR0L
	MOVIW	[FSR0]

	SUBWF	RHYTHM_SEQ_PTR, W		; Check if rhythm sequence pointer is > sequence length
    BTFSC   BORROW
		CLRF    RHYTHM_SEQ_PTR		; then reset rhythm sequence pointer
;	BTFSC	BORROW
;		CALL	ChangeChord
    
	LSRF	RHYTHM_SEQ_PTR, W
	MOVWF	BASS_SEQ_PTR
	LSRF	BASS_SEQ_PTR, F

	BTFSS	AUTO_BASS				; If no auto bass, then clear bass sequence pointer..
		CLRF	BASS_SEQ_PTR

InterruptExit:
    RETFIE


NoRhythm:
	CLRF	RHYTHM_SEQ_PTR		; We need to clear rhythm pointers
	CLRF	BASS_SEQ_PTR
	MOVLW	11000000b
	MOVWF	RHYTHM_SEQ_VAL		; And set triggers to output bass and chord
	BTFSC	MEMORY_MODE			; Are we in memory mode?
		GOTO	NoRhythmOutput
	BTFSS	CHORD_PRESSED		; Are we pressing a chord?
		CLRF	RHYTHM_SEQ_VAL

NoRhythmOutput:
	BSF		TRIGGER_REQ
	GOTO	InterruptExit

;ChangeChord:
;	INCF    CURRENT_CHORD   ; Increment current chord
;    MOVF    CURRENT_CHORD, W
;    SUBLW   12		    ; If current chord < 12
;    BTFSS   ZERO
;		GOTO    InterruptExit   ; then Exit
;    CLRF    CURRENT_CHORD   ; else, reset current chord
;	RETURN
    
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
;    BSF	    TEST_PIN
    
    MOVLW   #CHORD_BUFF2_LO  ; Assume chord buffer 2
    BTFSS   BUFFER_ONE
		MOVLW   #CHORD_BUFF1_LO  ; But use chord buffer 1 if else
    MOVWF   FSR1L
    CLRF    FSR1H
    
;----------------- Chord Sample Generation  
    MOVLW   16		; Setup loop that generates 16 chord samples
    MOVWF   LOOP_VAR
GenerateChordSample:
	CLRF	SAMPLE_HI
	
	MOVLW	HIGH NOTE_TO_PHASE_ACC	; Setup FSR0 to read from note_to_phase_acc
	MOVWF	FSR0H

    MOVF    CHORDB_NOTE, W	; Load chord bass note
    ADDWF   CHORDB_NOTE, W
    ADDWF   CHORDB_NOTE, W	; Mult by 3, to fit phase acc table
    MOVWF   FSR0L
    MOVIW   [FSR0]
    ADDWF   CHORDB_PHASE_LO, F
    MOVIW   1[FSR0]
    ADDWFC  CHORDB_PHASE_MID, F
    MOVIW   2[FSR0]
    ADDWFC  CHORDB_PHASE_HI, F

	MOVF	CHORD1_NOTE, W		; Load in the note
	ADDWF	CHORD1_NOTE, W
	ADDWF	CHORD1_NOTE, W		; Mult by 3 as phase accumulators are 24 bit
	MOVWF	FSR0L
	MOVIW	[FSR0]			; Do phase accumulator addition
	ADDWF   CHORD1_PHASE_LO, F
	MOVIW	1[FSR0]
	ADDWFC  CHORD1_PHASE_MID, F
	MOVIW	2[FSR0]
	ADDWFC  CHORD1_PHASE_HI, F
	
	MOVF	CHORD2_NOTE, W		; Load in the note
	ADDWF	CHORD2_NOTE, W		; Multiply it by two (as phase accumulators are 16 bit)
	ADDWF	CHORD2_NOTE, W		; Multiply it by 3!! (24 bit)
	MOVWF	FSR0L
	MOVIW	[FSR0]			; Do phase accumulator addition
	ADDWF   CHORD2_PHASE_LO, F
	MOVIW	1[FSR0]
	ADDWFC  CHORD2_PHASE_MID, F
	MOVIW	2[FSR0]
	ADDWFC  CHORD2_PHASE_HI, F

	MOVF	CHORD3_NOTE, W		; Load in the note
	ADDWF	CHORD3_NOTE, W		; Multiply it by two (as phase accumulators are 16 bit)
	ADDWF	CHORD3_NOTE, W		; Multiply it by 3!! (24 bit)
	MOVWF	FSR0L
	MOVIW	[FSR0]			; Do phase accumulator addition
	ADDWF   CHORD3_PHASE_LO, F
	MOVIW	1[FSR0]
	ADDWFC  CHORD3_PHASE_MID, F
	MOVIW	2[FSR0]
	ADDWFC  CHORD3_PHASE_HI, F

	MOVLW	HIGH CHORD_WAVE	
	MOVWF	FSR0H			; Wave lookup table select
	
	MOVF	CHORD1_PHASE_HI, W	; Look up wavetable and add to sample output
	MOVWF	FSR0L
	MOVIW	[FSR0]
	MOVWF	SAMPLE_LO
	
	MOVF	CHORD2_PHASE_HI, W
	MOVWF	FSR0L
	MOVIW	[FSR0]
	ADDWF	SAMPLE_LO, F
	BTFSC	CARRY
	    INCF	SAMPLE_HI, F
	
	MOVF	CHORD3_PHASE_HI, W
	MOVWF	FSR0L
	MOVIW	[FSR0]
	ADDWF	SAMPLE_LO, F
	BTFSC	CARRY
	    INCF	SAMPLE_HI, F

	MOVF	CHORDB_PHASE_HI, W
	MOVWF	FSR0L
	MOVIW	[FSR0]
	ADDWF	SAMPLE_LO, F
	BTFSC	CARRY
	    INCF	SAMPLE_HI, F
	
	
	MOVF    SAMPLE_LO, W	    ; Save sample output to buffer
	MOVWI	[FSR1]
	MOVF	SAMPLE_HI, W
	MOVWI	16[FSR1]
	INCF    FSR1L, F

	DECFSZ  LOOP_VAR, F	    ; Onto the next sample,,
	    GOTO    GenerateChordSample

;----------------- Bass Sample Generation
	MOVLW   #CHORD_BUFF2_LO  ; Assume chord buffer 2
    BTFSS   BUFFER_ONE
		MOVLW   #CHORD_BUFF1_LO  ; But use chord buffer 1 if else
    MOVWF   FSR1L
	INCF	FSR1H, F

	MOVLW   16		; Setup loop that generates 16 bass samples
    MOVWF   LOOP_VAR
GenerateBassSample:
	MOVLW	HIGH NOTE_TO_PHASE_ACC	; Setup FSR0 to read from note_to_phase_acc
	MOVWF	FSR0H

    MOVF    BASS_NOTE, W	; Load  bass note
    ADDWF   BASS_NOTE, W
    ADDWF   BASS_NOTE, W	; Mult by 3, to fit phase acc table
    MOVWF   FSR0L
    MOVIW   [FSR0]
    ADDWF   BASS_PHASE_LO, F
    MOVIW   1[FSR0]
    ADDWFC  BASS_PHASE_MID, F
    MOVIW   2[FSR0]
    ADDWFC  BASS_PHASE_HI, F

	MOVLW	HIGH BASS_WAVE	
	MOVWF	FSR0H			; Wave lookup table select
	
	MOVF	BASS_PHASE_HI, W	; Look up wavetable and add to sample output
	MOVWF	FSR0L
	MOVIW	[FSR0]
	MOVWF	SAMPLE_LO

	MOVF    SAMPLE_LO, W	    ; Save sample output to buffer
	MOVWI	[FSR1]
	INCF    FSR1L, F

	DECFSZ  LOOP_VAR, F	    ; Onto the next sample,,
	    GOTO    GenerateBassSample

;----------------- Fulfillment
    BCF	    SAMPLES_REQ	    ; We've fulfilled the request for more samples
;    BCF	    TEST_PIN

	MOVLW	2
	ADDWF	KEYREQ_OVERFLOW, F
	BTFSC	CARRY
		BSF		KEYSCAN_REQ		; Lets request a keyscan
    
    RETURN
    

;-------------------------------------------------------------------------------
;	KEYSCAN
;-------------------------------------------------------------------------------
KeyScan:
	MOVLW	HIGH KEYS
	MOVWF	FSR0H
	MOVLW	LOW KEYS
	MOVWF	FSR0L
	MOVLW   12		; Setup loop that clears 12 keys
    MOVWF   LOOP_VAR
	MOVLW	0
KeyScanLoopClear:
	MOVWI	FSR0++
	DECFSZ	LOOP_VAR, F
		GOTO	KeyScanLoopClear

	MOVLW	LOW KEYS
	MOVWF	FSR0L
	BSF		C1		; Select column 1
	BCF		SER_LD	; Load keys into shift registers
	BSF		SER_LD	
	MOVLW   12		; Setup loop that scans 12 keys
    MOVWF   LOOP_VAR
KeyScanLoopMajor:
	MOVLW	1
	BTFSC	SER_DAT_I
		ADDWF	INDF0, F
	INCF	FSR0L, F
	BSF		SER_CLK
	BCF		SER_CLK
	DECFSZ	LOOP_VAR, F
		GOTO	KeyScanLoopMajor
	BCF		C1

	MOVLW	LOW KEYS
	MOVWF	FSR0L
	BSF		C2		; Select column 2
	BCF		SER_LD	; Load keys into shift registers
	BSF		SER_LD	
	MOVLW   12		; Setup loop that scans 12 keys
    MOVWF   LOOP_VAR
KeyScanLoopMinor:
	MOVLW	2
	BTFSC	SER_DAT_I
		ADDWF	INDF0, F
	INCF	FSR0L, F
	BSF		SER_CLK
	BCF		SER_CLK
	DECFSZ	LOOP_VAR, F
		GOTO	KeyScanLoopMinor
	BCF		C2

	MOVLW	LOW KEYS
	MOVWF	FSR0L
	BSF		C3		; Select column 3
	BCF		SER_LD	; Load keys into shift registers
	BSF		SER_LD	
	MOVLW   12		; Setup loop that scans 12 keys
    MOVWF   LOOP_VAR
KeyScanLoop7:
	MOVLW	4
	BTFSC	SER_DAT_I
		ADDWF	INDF0, F
	INCF	FSR0L, F
	BSF		SER_CLK
	BCF		SER_CLK
	DECFSZ	LOOP_VAR, F
		GOTO	KeyScanLoop7
	BCF		C3

	BCF		KEYSCAN_REQ		; We've fulfilled the request for a keyscan

	RETURN
    
;-------------------------------------------------------------------------------
;	TRIGGER SHIFT REGISTER
;-------------------------------------------------------------------------------
OutputTriggers:
	MOVF	RHYTHM_SEQ_VAL, W
	MOVWF	TEMP		; Temp = Rhythm sequence value

	BCF		SER_DAT_O	; Data out might be high because it's shared with serial load
	MOVLW   8			; Setup loop that shifts out 8 times
    MOVWF   LOOP_VAR
OutputTriggersLoop:
	LSLF	TEMP, F		; Shift next trigger into carry bit
	BTFSC	CARRY
		BSF	SER_DAT_O	; If carry, output 1
	BTFSS	CARRY
		BCF	SER_DAT_O	; else, output 0

	BSF		SER_CLK		; Pulse clock
	BCF		SER_CLK

	DECFSZ	LOOP_VAR, F
		GOTO	OutputTriggersLoop

	
	BSF		SER_RCLK	; Update latches in shift register
	BCF		SER_RCLK


	BCF		TRIGGER_REQ	; We've fulfilled the request for a trigger output

	RETURN

;-------------------------------------------------------------------------------
;	RUNTIME
;-------------------------------------------------------------------------------
Main:
	
	BTFSC   SAMPLES_REQ
		CALL    SampleGeneration    ; If we require more samples, let's generate some!

    BTFSC	KEYSCAN_REQ
		CALL	KeyScan				; let's scan the keyboard!

	BTFSC	TRIGGER_REQ
		CALL	OutputTriggers		; output triggers,,
    
    GOTO    Main

    END	    ; We should never reach here