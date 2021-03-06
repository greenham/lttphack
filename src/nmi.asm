pushpc
;======================================================================================
; Improves the speed of OAM clearing by 2 scanlines; credit: MathOnNapkins
; Has no effect on anything
; But it gives us consistent improvements to account for practice hack lag
;======================================================================================
org $00841E ; ClearOamBuffer
	PHP : REP #$10

	; first half
	LDX #$8001 : STX $4300
	LDX #$0801 : STX $2181 : STZ $2183

	LDX.w #OAM_Cleaner : STX $4302
	LDA.b #OAM_Cleaner>>16 : STA $4304
	LDX #$0080 : STX $4305
	LDA #$01 : STA $420B

	; second half
	LDX.w #OAM_Cleaner : STX $4302
	LDX #$0901 : STX $2181
	LDX #$0080 : STX $4305

	STA $420B

	PLP : RTS
warnpc $008489

; NMI
;
; Expands the NMI (code run at the end of each frame)

; NMI hook
org $0080D5
	; 0080D1 LDA #$0000
	; 0080D4 TCD
	; 0080D5 PHK
	; 0080D6 PLB
	; 0080D7 SEP #$30
	JSL nmi_expand

org $008174
LDA $1C : STA $AB : NOP
LDA $1D : STA $AC : NOP

;org $0081A0 ; save camera correction for NMI expansion
;	BRA + ; save time during NMI
;org $0081B8 : +

; HUD update hook
org $008B6B
	; 008b6b ldx $0219
	; 008b6e stx $2116
	;JSL nmi_hud_update
	;NOP #2

;org $008220
org $00821B
	; LDA $9B
	; STA $420C
	JSL nmi_hud_update
	NOP

; NMI HOOK
org $0089C2
nmi_hook:
	TCD : PHK : PLB
	JSL nmi_expand
	RTS

warnpc $0089DF
; Unused $17 function repurposed
org $008C8A
	dw NMI_UpdatePracticeHUD ; $17=0x06

org $00EA79 ; seems unused
NMI_UpdatePracticeHUD:
	REP #$20
	LDX #$80 : STX $2115
	LDA #$6C00 : STA $2116

	LDA #$1801 : STA $4300
	LDA.w #!menu_dma_buffer : STA $4302
	LDX.b #!menu_dma_buffer>>16 : STX $4304
	LDA #$0800 : STA $4305

	LDX #$01 : STX $420B
	SEP #$20
	RTS

warnpc $00EAE5

; The time this routine takes isn't relevant
; since it's never during game play
org $00E36A
	JSL LoadCustomHUDGFX
	PLB : RTL

pullpc

; Needs to leave AI=8
nmi_expand:
	; enters AI=16
	SEP #$30
	; this covers the PHK : PLB we overwrote
	PHA ; A is 0 from right before the hook
	PLB ; and that happens to be the bank we want

	LDA !disabled_layers : TRB $AB : TRB $AC
	REP #$20
	LDA $AB : STA $212C

	SEP #$28 ; a=8, BCD=on
	LDA !lowram_last_frame_did_saveload : BEQ .update_counters
	JMP .dont_update_counters

.update_counters
	; if $12 = 1, then we weren't done with game code
	; that means we're in a lag frame
	LDA $12 : STA !lag_cache : LSR

	REP #$20
	LDA !lag_frames : ADC #$0000 ; carry set from $12 being 1
	STA !lag_frames

	; cycle controlled room time
	SEP #$21 ; include carry
	LDA !room_time_F : ADC #$00
	CMP #$60
	BCS .rtF60

.rtFOK
	BCC ++ ; 3 cycles

.rtF60 ; 1 cycle for branch
	LDA #$00 ; 2 cycles

++	STA !room_time_F

	REP #$20 ; seconds have 3 digits
	LDA !room_time_S : ADC #$0000 ; increments by 1 if F>=60
	STA !room_time_S

	; cycle controlled segment time
	SEP #$21 ; include carry
	LDA !seg_time_F : ADC #$00
	CMP #$60
	BCS .stF60

.stFOK
	BCC ++ ; 3 cycles

.stF60 ; 1 cycle for branch
	LDA #$00 ; 2 cycles

++	STA !seg_time_F

	LDA !seg_time_S : ADC #$00 ; increments by 1 if F>=60
	CMP #$60
	BCS .stS60

.stSOK
	BCC ++ ; 3 cycles

.stS60 ; 1 cycle for branch
	LDA #$00 ; 2 cycles

++	STA !seg_time_S

	REP #$20
	LDA !seg_time_M : ADC #$0000 ; increments by 1 if S>=60
	STA !seg_time_M

.dont_update_counters
	CLD
	JSR dotimers
	SEP #$30
	STZ !lowram_last_frame_did_saveload
	RTL

nmi_hud_update:
	; Movie stuff commented out while it's not needed
;	LDX #$6360 : STX $2116

;	; $7EC700 is the WRAM buffer for this data
;	LDX.w #!ram_movie_hud : STX $4302
;	LDA.b #!ram_movie_hud>>16 : STA $4304
;	LDX #$0040 : STX $4305 ; number of bytes to transfer is 330
;	LDA #$01 : STA $420B ; refresh BG3 tilemap data with this transfer on channel 0
	REP #$21 ; carry only needs clearing once
	SEP #$10

	LDX !lag_cache : BNE .dontbreakthings
	LDA !ram_doorwatch_toggle
	TAX
	BEQ .noDoorWatch
	LDX #$80 : STX $2115
	LDA #$6500 : STA $2116

	LDA #$1801 : STA $4300
	LDA.w #!dg_dma_buffer : STA $4302
	LDX.b #!dg_dma_buffer>>16 : STX $4304
	LDA #$0100 : STA $4305

	LDY #$01 : STY $420B

.noDoorWatch
	; force heartlag update
	LDX !do_heart_lag : BEQ .dontbreakthings
	LDA #$C118>>1 : STA $2116
	LDA.l !POS_MEM_HEARTLAG : STA $2118

.dontbreakthings
	STZ !do_heart_lag
	LDX $13
	STX $2100

	RTL

;===========================================
; OAM cleaner optimization
;===========================================
macro OAMVClear(pos)
	db $F0, <pos>+$05, $F0, <pos>+$09, $F0, <pos>+$0D, $F0, <pos>+$11
endmacro

OAM_Cleaner:
	%OAMVClear($00)
	%OAMVClear($10)
	%OAMVClear($20)
	%OAMVClear($30)
	%OAMVClear($40)
	%OAMVClear($50)
	%OAMVClear($60)
	%OAMVClear($70)
	%OAMVClear($80)
	%OAMVClear($90)
	%OAMVClear($A0)
	%OAMVClear($B0)
	%OAMVClear($C0)
	%OAMVClear($D0)
	%OAMVClear($E0)
	%OAMVClear($F0)