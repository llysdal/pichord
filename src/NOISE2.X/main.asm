 title  "Electric Druid White+Pink Noise Generator"
;============================================================================
; The Electric Druid White+Pink Noise Generator
;============================================================================
; Legal stuff
; Copyright 2019 Tom Wiltshire for Electric Druid. Some rights reserved.
; This code is shared under a Creative Commons
; Attribution-NonCommercial-ShareAlike 4.0 International Licence
; For full details see www.electricdruid.net/legalstuff
; or get in touch at www.electricdruid.net/contact.
;============================================================================
; Started with the Pentanoise.asm code, 21th Nov 2015, Carunchoso.

; Hardware Notes:
;   PIC16F18313 running at 32 MHz using the internal clock
; 1  +5V
; 2  RA5			: Unused
; 3  RA4			: White Noise Output
; 4  RA3/~MCLR/Vpp	: Unused Input
; 5  RA2/ AN2		: Unused
; 6  RA1/AN1		: Unused
; 7  RA0/AN0		: Pink Noise Output (NOTE: must be buffered)
; 8  Gnd

; Noise2.asm, 23rd January 2019
; A second-generation noise chip with both white and pink outputs.
; I've moved this code from the 12F1501 to the 16F18313 and increased the
; processor speed to 32MHz. This gives me 80 instructions if I am to hit a 
; 100KHz output rate.
; The code implements a Voss-McCartney algorithm for the pink noise.
; Both the tree structure and the addition of the output bits from the various
; octaves of LFSRs are done by look-ups.
; We use 14 octaves of LFSRs, plus one updated-every-sample white noise source.
; This gives us a convenient range of 0-15 bits set, which we can pass to the
; resistor-string DAC.
; The white noise output is done as before, with a simple digital IO pin.

   LIST R=DEC
    INCLUDE <p16f18313.inc>
    Errorlevel -302

; 16F18313 Configuration
    __CONFIG _CONFIG1, _FEXTOSC_OFF & _RSTOSC_HFINT32 & _CLKOUTEN_OFF & _CSWEN_OFF & _FCMEN_OFF
    __CONFIG _CONFIG2, _MCLRE_OFF & _PWRTE_OFF &_WDTE_OFF & _LPBOREN_OFF &_BOREN_OFF & _PPS1WAY_OFF & _STVREN_OFF & _DEBUG_OFF
    __CONFIG _CONFIG3, _WRT_OFF & _LVP_OFF
    __CONFIG _CONFIG4, _CP_OFF & _CPD_OFF

;----------------------------------------------------------------------------
;	Bank 0 Variables
;----------------------------------------------------------------------------
; CBLOCK 0x020
; Nuffin' in 'ere
; ENDC

;----------------------------------------------------------------------------
; 0x70-0x7F  Common RAM - Special variables available in all banks
;----------------------------------------------------------------------------
 CBLOCK 0x070
	; LFSR 1, a 31-bit register
	LFSR1_1
	LFSR1_2
	LFSR1_3
	LFSR1_4
	; LFSR 2, a 23-bit register
	LFSR2_1
	LFSR2_2
	LFSR2_3
	; Temporary storage
	TEMP
	
	; Tree structure counter
	COUNT_LO
	COUNT_HI
	
	; The outputs from all the LFSRs (these get added together)
	OUTPUT_LO
	OUTPUT_HI
	
; Note that using variables in Common RAM saves me having to switch
; banks when I do the output to the DAC or to LATA
 ENDC

;----------------------------------------------------------------------------
;	DEFINE STATEMENTS
;----------------------------------------------------------------------------

; Useful bit definitions for clarity	
#define ZEROBIT				STATUS,Z		; Zero Flag
#define CARRY				STATUS,C		; Carry
#define BORROW				STATUS,C		; Borrow is the same as Carry

;----------------------------------------------------------------------------
;	In the beginning, all was 0x000 and NOP...
;----------------------------------------------------------------------------
	org     0x0000				; Processor reset vector
	nop							; for ICD use

;----------------------------------------------------------------------------
;	MAIN PROGRAM
; This sets everything up before moving into the sample gen/ADC reading loop.
;----------------------------------------------------------------------------
Main:
	; Clock is set for 32MHz internal by config flags

	; Set up the IO Ports
	movlb	D'1'				; Bank 1
	movlw	B'11101111'			; Only RA4 is output
	movwf	TRISA				; (Although RA0 is DAC OUT, TRISA is overridden)

	; Set up weak pull-ups
	movlb	D'4'				; Bank 4
	clrf	WPUA				; No weak pull-ups

 	; Set up DAC
	movlb	D'2'				; Bank 2
	movlw	B'10100000'			; DAC enabled, Output enabled, Vdd, Vss.
	movwf	DACCON0
	movlw	D'16'				; Start at midpoint voltage?
	movwf	DACCON1
	
	; Clear the outputs initially
	;	movlb	D'2'				; Bank 2
	clrf	LATA

	; Set up initial values of the variables

	; Note that the bank doesn't matter for the variables, since they
	; are in Common RAM

	; Set up random number generator shift registers
	movlw	0x45				; Some non-zero value
	movwf	LFSR1_1
	movlw	0x57
	movwf	LFSR1_2
	movlw	0x9F
	movwf	LFSR1_3
	movlw	0xF2
	movwf	LFSR1_4
	movlw	0xD7
	movwf	LFSR2_1
	movlw	0xC8
	movwf	LFSR2_2
	movlw	0x79
	movwf	LFSR2_3
	
	; Clear counter
	clrf	COUNT_LO
	clrf	COUNT_HI
	
	; Set output at some arbitrary midpoint level
	movlw	0x6C
	movwf	OUTPUT_LO
	movlw	0x39
	movwf	OUTPUT_HI
	

;----------------------------------------------------------------------------
;	MAIN LOOP
; This generates new white and pink noise samples and outputs them
;----------------------------------------------------------------------------
; Note that we're still in Bank 2, and remain there throughout.
	
MainLoop:
;	Update the two LFSRs
;----------------------------------------------------
	
	; 31-bit LFSR with taps at 31 and 28
	;----------------------------------------------------
	; This is our white noise source, and is also the fixed white
	; noise element of the pink noise source.
	swapf	LFSR1_4, W	; Get tap 28
	movwf	TEMP
	rlf		LFSR1_4, W	; Get tap 31
	xorwf	TEMP, F
	; Shift the XORd bit into carry
	rlf		TEMP, F
	; Shift the register
	rlf		LFSR1_1, F
	rlf		LFSR1_2, F
	rlf		LFSR1_3, F
	rlf		LFSR1_4, F


	; 21-bit LFSR with taps at 21 and 19
	;----------------------------------------------------
	; This is used for the lower octaves
	rrf		LFSR2_3, W	; Get tap 19
	movwf	TEMP
	rrf		TEMP, F
	swapf	LFSR2_3, W	; Get tap 21
	xorwf	TEMP, F
	; Shift the XORd bit into carry
	rrf		TEMP, F
	; Shift the register
	rlf		LFSR2_1, F
	rlf		LFSR2_2, F
	rlf		LFSR2_3, F
; 18 to here

;	Update one of the LFSRs
;----------------------------------------------------

; First, we need to know which one we're updating
SelectOutput:
	; Update the tree structure counter
	movlw	D'1'
	addwf	COUNT_LO, f
	movlw	D'0'
	addwfc	COUNT_HI, f
	
	; Find out which output we need to update
	movf	COUNT_LO, w
; 23 to here
	call	TreeTable
; 29 to here
	
	; Update the correct output
    brw
    goto	Octave0				; Updated every 2nd sample
    goto	Octave1				; Updated every 4th sample
    goto	Octave2				; Updated every 8th sample
    goto	Octave3				; etc..
    goto	Octave4
    goto	Octave5
    goto	Octave6
    goto	Octave7
    goto	Octaves8to13		; These only come around every 256th sample
; 33 to here? (brw=2?)
    
Octave0:
	; We assume the bit is cleared, and then set it if neccessary
	bcf		OUTPUT_LO, 0
	btfsc	LFSR2_2, 0			; Doesn't really matter which LFSR bit we use
	bsf		OUTPUT_LO, 0
	; The other outputs are done in exactly the same way
	goto	Octaves8to13Compensation

Octave1:
	bcf		OUTPUT_LO, 1
	btfsc	LFSR2_2, 0		
	bsf		OUTPUT_LO, 1
	goto	Octaves8to13Compensation
	
Octave2:
	bcf		OUTPUT_LO, 2
	btfsc	LFSR2_2, 0		
	bsf		OUTPUT_LO, 2
	goto	Octaves8to13Compensation
	
Octave3:
	bcf		OUTPUT_LO, 3
	btfsc	LFSR2_2, 0		
	bsf		OUTPUT_LO, 3
	goto	Octaves8to13Compensation
	
Octave4:
	bcf		OUTPUT_LO, 4
	btfsc	LFSR2_2, 0		
	bsf		OUTPUT_LO, 4
	goto	Octaves8to13Compensation
	
Octave5:
	bcf		OUTPUT_LO, 5
	btfsc	LFSR2_2, 0		
	bsf		OUTPUT_LO, 5
	goto	Octaves8to13Compensation
	
Octave6:
	bcf		OUTPUT_LO, 6
	btfsc	LFSR2_2, 0		
	bsf		OUTPUT_LO, 6
	goto	Octaves8to13Compensation
	
Octave7:
	bcf		OUTPUT_LO, 7
	btfsc	LFSR2_2, 0		
	bsf		OUTPUT_LO, 7
	goto	Octaves8to13Compensation

;	Octaves 8 to 13
;----------------------------------------------------	
; Once every 256 samples we jump here and update one of the lowest frequency
; noise sources. The process is exactly the same as above.
Octaves8to13:
	; Find out which output we need to update
	movf	COUNT_HI, w
	andlw	0x3F				; Limit this upper byte to 6 LFSRs
	call	TreeTable
	; Update the correct output
    brw
    goto	Octave8				; Updated every 512th sample
    goto	Octave9				; Updated every 1024th sample
    goto	Octave10			; Updated every 2048th sample
    goto	Octave11			; etc..
    goto	Octave12
    goto	Octave13
    goto	AddWhiteNoise

Octave8:
	bcf		OUTPUT_HI, 0
	btfsc	LFSR2_2, 0		
	bsf		OUTPUT_HI, 0
	goto	AddWhiteNoise
	
Octave9:
	bcf		OUTPUT_HI, 1
	btfsc	LFSR2_2, 0		
	bsf		OUTPUT_HI, 1
	goto	AddWhiteNoise
	
Octave10:
	bcf		OUTPUT_HI, 2
	btfsc	LFSR2_2, 0		
	bsf		OUTPUT_HI, 2
	goto	AddWhiteNoise
	
Octave11:
	bcf		OUTPUT_HI, 3
	btfsc	LFSR2_2, 0		
	bsf		OUTPUT_HI, 3
	goto	AddWhiteNoise
	
Octave12:
	bcf		OUTPUT_HI, 4
	btfsc	LFSR2_2, 0		
	bsf		OUTPUT_HI, 4
	goto	AddWhiteNoise
	
Octave13:
	bcf		OUTPUT_HI, 5
	btfsc	LFSR2_2, 0		
	bsf		OUTPUT_HI, 5
	goto	AddWhiteNoise
	
; A little delay to account for NOT having done the Octaves8to15 section
Octaves8to13Compensation:
	nop							; 11 instructions is the difference between
	nop							; the 0-7 octave path and the 8-13 octave
	nop							; path
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop


;	Add white noise every sample to fill in the nulls
;----------------------------------------------------
AddWhiteNoise:
	; This uses the other LFSR, but is otherwise identical
	bcf		OUTPUT_HI, 6
	btfsc	LFSR1_4, 0		
	bsf		OUTPUT_HI, 6
	

;	Add up how many of the outputs are set
;----------------------------------------------------
; We do this with an 8-bit look-up to save actual adding
AddUpBits:
	; Add up the number of bits from Octaves 0-7
	movf	OUTPUT_LO, w
	call	NumOfBitsSet
	movwf	TEMP				; Store it in TEMP
	; Add up the number of bits from Octaves 8-15
	movf	OUTPUT_HI, w
	call	NumOfBitsSet
	addwf	TEMP, f				; Add the number in TEMP to get the total
	; We have the total number of bits in TEMP
	
OutputToDAC:
	lslf	TEMP, w				; Shift up to 0-30 range
	movwf	DACCON1
	
OutputWhiteNoise:
	; We also output a simple white noise source on another bit
	movf	LFSR1_4, w		; Bit 4 is our output, so we're using bit 4
	movwf	LATA

	; That's the lot! How big is the loop?!?
	goto	MainLoop

;----------------------------------------------------------------------------
;	Tree Structure table
;----------------------------------------------------------------------------
; The Voss-McCartney algorithm uses a clever tree structure to decide which
; output should be updated on any particular occasion. There are various ways
; to generarate it, but here we just use a look-up.

TreeTable:
	brw
	dt	D'0', D'1', D'0', D'2', D'0', D'1', D'0', D'3'
	dt	D'0', D'1', D'0', D'2', D'0', D'1', D'0', D'4'
	dt	D'0', D'1', D'0', D'2', D'0', D'1', D'0', D'3'
	dt	D'0', D'1', D'0', D'2', D'0', D'1', D'0', D'5'
	dt	D'0', D'1', D'0', D'2', D'0', D'1', D'0', D'3'
	dt	D'0', D'1', D'0', D'2', D'0', D'1', D'0', D'4'
	dt	D'0', D'1', D'0', D'2', D'0', D'1', D'0', D'3'
	dt	D'0', D'1', D'0', D'2', D'0', D'1', D'0', D'6'

	dt	D'0', D'1', D'0', D'2', D'0', D'1', D'0', D'3'
	dt	D'0', D'1', D'0', D'2', D'0', D'1', D'0', D'4'
	dt	D'0', D'1', D'0', D'2', D'0', D'1', D'0', D'3'
	dt	D'0', D'1', D'0', D'2', D'0', D'1', D'0', D'5'
	dt	D'0', D'1', D'0', D'2', D'0', D'1', D'0', D'3'
	dt	D'0', D'1', D'0', D'2', D'0', D'1', D'0', D'4'
	dt	D'0', D'1', D'0', D'2', D'0', D'1', D'0', D'3'
	dt	D'0', D'1', D'0', D'2', D'0', D'1', D'0', D'7'

	dt	D'0', D'1', D'0', D'2', D'0', D'1', D'0', D'3'
	dt	D'0', D'1', D'0', D'2', D'0', D'1', D'0', D'4'
	dt	D'0', D'1', D'0', D'2', D'0', D'1', D'0', D'3'
	dt	D'0', D'1', D'0', D'2', D'0', D'1', D'0', D'5'
	dt	D'0', D'1', D'0', D'2', D'0', D'1', D'0', D'3'
	dt	D'0', D'1', D'0', D'2', D'0', D'1', D'0', D'4'
	dt	D'0', D'1', D'0', D'2', D'0', D'1', D'0', D'3'
	dt	D'0', D'1', D'0', D'2', D'0', D'1', D'0', D'6'

	dt	D'0', D'1', D'0', D'2', D'0', D'1', D'0', D'3'
	dt	D'0', D'1', D'0', D'2', D'0', D'1', D'0', D'4'
	dt	D'0', D'1', D'0', D'2', D'0', D'1', D'0', D'3'
	dt	D'0', D'1', D'0', D'2', D'0', D'1', D'0', D'5'
	dt	D'0', D'1', D'0', D'2', D'0', D'1', D'0', D'3'
	dt	D'0', D'1', D'0', D'2', D'0', D'1', D'0', D'4'
	dt	D'0', D'1', D'0', D'2', D'0', D'1', D'0', D'3'
	dt	D'0', D'1', D'0', D'2', D'0', D'1', D'0', D'8'


;----------------------------------------------------------------------------
;	Number of bits set table
;----------------------------------------------------------------------------
; For each number 0-255, this returns how many bits are set
; This saves actually adding up how many bits are set in a byte.
; It's always simpler just to look this stuff up if it can be done.

NumOfBitsSet:
	brw
	dt	D'0', D'1', D'1', D'2', D'1', D'2', D'2', D'3'
	dt	D'1', D'2', D'2', D'3', D'2', D'3', D'3', D'4'
	dt	D'1', D'2', D'2', D'3', D'2', D'3', D'3', D'4'
	dt	D'2', D'3', D'3', D'4', D'3', D'4', D'4', D'5'
	dt	D'1', D'2', D'2', D'3', D'2', D'3', D'3', D'4'
	dt	D'2', D'3', D'3', D'4', D'3', D'4', D'4', D'5'
	dt	D'2', D'3', D'3', D'4', D'3', D'4', D'4', D'5'
	dt	D'3', D'4', D'4', D'5', D'4', D'5', D'5', D'6'

	dt	D'1', D'2', D'2', D'3', D'2', D'3', D'3', D'4'
	dt	D'2', D'3', D'3', D'4', D'3', D'4', D'4', D'5'
	dt	D'2', D'3', D'3', D'4', D'3', D'4', D'4', D'5'
	dt	D'3', D'4', D'4', D'5', D'4', D'5', D'5', D'6'
	dt	D'2', D'3', D'3', D'4', D'3', D'4', D'4', D'5'
	dt	D'3', D'4', D'4', D'5', D'4', D'5', D'5', D'6'
	dt	D'3', D'4', D'4', D'5', D'4', D'5', D'5', D'6'
	dt	D'4', D'5', D'5', D'6', D'5', D'6', D'6', D'7'

	dt	D'1', D'2', D'2', D'3', D'2', D'3', D'3', D'4'
	dt	D'2', D'3', D'3', D'4', D'3', D'4', D'4', D'5'
	dt	D'2', D'3', D'3', D'4', D'3', D'4', D'4', D'5'
	dt	D'3', D'4', D'4', D'5', D'4', D'5', D'5', D'6'
	dt	D'2', D'3', D'3', D'4', D'3', D'4', D'4', D'5'
	dt	D'3', D'4', D'4', D'5', D'4', D'5', D'5', D'6'
	dt	D'3', D'4', D'4', D'5', D'4', D'5', D'5', D'6'
	dt	D'4', D'5', D'5', D'6', D'5', D'6', D'6', D'7'

	dt	D'2', D'3', D'3', D'4', D'3', D'4', D'4', D'5'
	dt	D'3', D'4', D'4', D'5', D'4', D'5', D'5', D'6'
	dt	D'3', D'4', D'4', D'5', D'4', D'5', D'5', D'6'
	dt	D'4', D'5', D'5', D'6', D'5', D'6', D'6', D'7'
	dt	D'3', D'4', D'4', D'5', D'4', D'5', D'5', D'6'
	dt	D'4', D'5', D'5', D'6', D'5', D'6', D'6', D'7'
	dt	D'4', D'5', D'5', D'6', D'5', D'6', D'6', D'7'
	dt	D'5', D'6', D'6', D'7', D'6', D'7', D'7', D'8'

; We never reach here
	end 