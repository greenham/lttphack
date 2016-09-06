; $1100 = first line -> $D100 in VRAM
; $1140 = second line
; $1780 = last line
; $40 bytes/32 tiles per line.

table chrmap.tbl

org $00806D
    db #$00
org $008089
    db #$80
org $0080A5
    db #$25

macro inc_mode()
    ; Assumes A=8
    LDA $11 : INC : STA $11
endmacro

org $258000
CM_Main:
    PHB : PHK : PLB

    JSR CM_Local

    PLB
    RTL


CM_Local:
    LDA $11

    JSL !UseImplicitRegIndexedLocalJumpTable

    dw CM_Init
    dw CM_DrawMenu
    dw CM_MenuDown
    dw CM_Active
    dw CM_MenuUp
    dw CM_Return


CM_Init:
    JSR cm_clear_buffer
    JSR cm_clear_stack

  %ppu_off()
    JSR cm_transfer_tilemap
  %ppu_on()

  %a16()
    LDA #$0000 : STA !lowram_cm_menu_stack_index
    LDA #cm_mainmenu_indices : STA !ram_cm_menu_stack
  %a8()

    %inc_mode()
    RTS


CM_DrawMenu:
    ; play sound effect for opening item menu
    LDA.b #$11 : STA $012F

    JSR cm_draw_active_menu

    ; tell NMI to update tilemap
    LDA.b #$01 : STA $17
    LDA.b #$22 : STA $0116

    %inc_mode()
    RTS


CM_MenuDown:
  %a16()
    LDA $EA : SEC : SBC.w #$0008 : STA $EA
    CMP.w #$FF18
  %a8()

    BNE .notDoneScrolling

    %inc_mode()

  .notDoneScrolling
    RTS


CM_Active:
    ; $F4 = BYST | udlr
    ; $F6 = AXLR | ....

    LDA $F4 : CMP #$10 : BEQ .pressed_start
    CMP #$04 : BEQ .pressed_down
    CMP #$08 : BEQ .pressed_up
    LDA $F6 : CMP #$80 : BEQ .pressed_a

    ; Did not press anything
    BRA .done

  .pressed_start
    %inc_mode()
    BRA .done

  .pressed_up
  %a16()
    LDX !lowram_cm_menu_stack_index
    LDA !lowram_cm_cursor, X : DEC : DEC : JSR cm_fix_cursor_wrap : STA !lowram_cm_cursor, X
  %a8()
    JSR cm_draw_active_menu
    BRA .did_update_gfx

  .pressed_down
  %a16()
    LDX !lowram_cm_menu_stack_index
    LDA !lowram_cm_cursor, X : INC : INC : JSR cm_fix_cursor_wrap : STA !lowram_cm_cursor, X
  %a8()
    JSR cm_draw_active_menu
    BRA .did_update_gfx

  .pressed_a
    JSR cm_execute_cursor
    JSR cm_draw_active_menu
    BRA .did_update_gfx

  .did_update_gfx
    ; tell NMI to update tilemap
    LDA.b #$01 : STA $17
    LDA.b #$22 : STA $0116

  .done
    RTS


CM_MenuUp:
  %a16()
    LDA $EA : CLC : ADC.w #$0008 : STA $EA
  %a8()

    BNE .notDoneScrolling

    %inc_mode()

  .notDoneScrolling
    RTS

CM_Return:
  %ppu_off()
    JSL load_default_tileset
  %ppu_on()

    LDA !ram_cm_old_gamemode : STA $10
    LDA !ram_cm_old_submode : STA $11
    RTS


cm_clear_stack:
  ; assumes I=8
  %a16()
    LDX.b #$00
    LDA #$0000

  .loop

    STA !lowram_cm_cursor, X : STA !lowram_cm_menu_stack_index, X

    INX : INX : CPX.b #$10

    BNE .loop

  %a8()
    RTS


cm_clear_buffer:
  ; assumes I=8
  %a16()

    LDX.b #$00

    ; value of a transparent tile
    LDA #$207F

  .clearVramBuffer

    STA $1000, X : STA $1080, X
    STA $1100, X : STA $1180, X
    STA $1200, X : STA $1280, X
    STA $1300, X : STA $1380, X
    STA $1400, X : STA $1480, X
    STA $1500, X : STA $1580, X
    STA $1600, X : STA $1680, X
    STA $1700, X : STA $1780, X

    INX : INX : CPX.b #$80

    BNE .clearVramBuffer

  %a8()
    RTS


cm_transfer_tilemap:
    %i16()

    ; word-access, incr by 1
    LDA #$80 : STA $2115

    LDX #$7000 : STX $2116 ; VRAM address (E000 in vram)
    LDX #cm_hud_table : STX $4302 ; Source offset 
    LDA #$25 : STA $4304 ; Source bank
    LDX #$0740 : STX $4305 ; Size (0x10 = 1 tile)
    LDA #$01 : STA $4300 ; word, normal increment (DMA MODE)
    LDA #$18 : STA $4301 ; destination (VRAM write)
    LDA #$01 : STA $420B ; initiate DMA (channel 1)

    %i8()
    RTS

; ---------
; Draw
; ---------

cm_draw_active_menu:
    ; This functions sets:
    ; $00[0x2] = menu indices
    ; $02[0x2] = current menu item index
    ; then we call the action draw method, which can do whatever it wants.
  %ai16()
    STA !ram_debug
    LDX !lowram_cm_menu_stack_index
    LDA !ram_cm_menu_stack, X : STA $00
    LDY #$0000

  .next_item
    LDX !lowram_cm_menu_stack_index
    TYA : CMP !lowram_cm_cursor, X : BEQ .selected
    LDA #$0020
    BRA .not_selected

  .selected
    LDA #$0024
    
  .not_selected
    STA $0E
    LDA ($00), y : BEQ .end : STA $02

    PHY

    ; Pull out the action index, increment $02 so its ready for the associated
    ; draw function to use its data however it likes, and jump to it.
    LDA ($02) : TAX
    INC $02 : INC $02
    JSR (cm_action_draw_table, X)

    PLY
    INY : INY
    JMP .next_item

  .end
  %ai8()
    RTS


cm_draw_text:
    %a8()
    LDY #$0000

  .loop
    LDA ($02), y : CMP #$FF : BEQ .end
    STA $1000, X : INX
    LDA $0E : STA $1000, X : INX
    INY : JMP .loop

  .end
    %a16()
    RTS


; ---------
; Cursor
; ---------

cm_fix_cursor_wrap:
  ; X = !lowram_cm_menu_stack_index
  %ai16()
    PHA
    LDA !ram_cm_menu_stack, X : STA $00
    LDY #$0000

  .loop
    LDA ($00), y : BEQ .after_loop
    INY : INY
    JMP .loop

  .after_loop
    ; Top of stack = cursor
    ; Y = max + 2
    STY $00
    PLA

    BMI .set_to_max
    CMP $00 : BEQ .set_to_zero : BCS .set_to_zero

    BRA .end

  .set_to_zero
    LDA #$0000
    BRA .end

  .set_to_max
    LDA $00
    DEC : DEC

  .end
  %ai8()
    RTS


cm_execute_cursor:
  %ai16()
    LDX !lowram_cm_menu_stack_index
    LDA !ram_cm_menu_stack, X : STA $00
    LDY !lowram_cm_cursor, X
    LDA ($00), y : STA $00

    LDA ($00) : INC $00 : INC $00 : TAX

    JSR (cm_action_execute_table, X)
  %ai8()
    RTS

; --------------
; Actions
; --------------

cm_action_execute_table:
    dw cm_action_toggle_byte
    dw cm_action_jsr
    dw cm_action_submenu
    dw cm_action_back

cm_action_toggle_byte:
  %a16()
    LDA ($00) : INC $00 : INC $00 : STA $02
  %a8()
    LDA ($00) : INC $00 : STA $04
    LDA [$02] : EOR #$01 : STA [$02]
    RTS

cm_action_jsr:
  %a16()
    LDA ($00) : INC $00 : INC $00 : STA $02
  %a8()
    LDX #$0000
    JSR ($0002, X)
    RTS

cm_action_submenu:
  %a16()
    LDA !lowram_cm_menu_stack_index : INC : INC : STA !lowram_cm_menu_stack_index : TAX
    LDA ($00) : INC $00 : INC $00 : STA !ram_cm_menu_stack, X
  %ai8()
    JSR cm_clear_buffer
  %i16()
    RTS

cm_action_back:
  %a16()
    LDA !lowram_cm_menu_stack_index : DEC : DEC : BPL .done

    LDA #$0000

  .done
    STA !lowram_cm_menu_stack_index
  %a8()
    RTS


cm_action_draw_table:
    dw cm_action_draw_toggle_byte
    dw cm_action_draw_jsr
    dw cm_action_draw_submenu
    dw cm_action_draw_back


cm_action_draw_toggle_byte:
    ; Find screen position from Y (item number)
    TYA : ASL : ASL : ASL : ASL : ASL
    CLC : ADC #$0144 : TAX

    ; grab the memory address (long)
    LDA ($02) : INC $02 : INC $02 : STA $04
    LDA ($02) : INC $02 : STA $06

    ; grab the value at that memory address
    LDA [$04] : BNE .checked
    LDA #$2472
    BRA .draw_text

  .checked
    LDA #$2473

  .draw_text
    ; draw checkbox and text
    STA $1000, X : INX : INX
    JSR cm_draw_text
    
    RTS

cm_action_draw_jsr:
    ; Find screen position from Y (item number)
    TYA : ASL : ASL : ASL : ASL : ASL
    CLC : ADC #$0144 : TAX

    INC $02 : INC $02
    JSR cm_draw_text
    
    RTS

cm_action_draw_submenu:
    ; Find screen position from Y (item number)
    TYA : ASL : ASL : ASL : ASL : ASL
    CLC : ADC #$0144 : TAX

    INC $02 : INC $02
    JSR cm_draw_text
    
    RTS

cm_action_draw_back:
    ; Find screen position from Y (item number)
    TYA : ASL : ASL : ASL : ASL : ASL
    CLC : ADC #$0144 : TAX

    JSR cm_draw_text
    
    RTS

; --------------
; MAIN MENU
; --------------

cm_mainmenu_indices:
    dw #cm_mainmenu_test_jsr
    dw #cm_mainmenu_test_submenu
    dw #cm_mainmenu_toggle_xy
    dw #cm_mainmenu_toggle_qw
    dw #cm_mainmenu_toggle_lit_rooms
    dw #cm_mainmenu_toggle_oob
    dw #$0000

cm_submenu_indices:
    dw #cm_menuitem_test_back
    dw #cm_mainmenu_test_submenu
    dw #cm_mainmenu_toggle_lit_rooms
    dw #cm_mainmenu_toggle_oob
    dw #$0000


cm_menuitem_test_back:
    dw !CM_ACTION_BACK
    db "Back", #$FF

cm_mainmenu_test_jsr:
    dw !CM_ACTION_JSR
    dw #tezt
    db "JSR dat coord", #$FF

cm_mainmenu_test_submenu:
    dw !CM_ACTION_SUBMENU
    dw #cm_submenu_indices
    db "Submenu", #$FF

cm_mainmenu_toggle_xy:
    dw !CM_ACTION_TOGGLE_BYTE
    dl !ram_xy_toggle
    db "Coordinates", #$FF

cm_mainmenu_toggle_qw:
    dw !CM_ACTION_TOGGLE_BYTE
    dl !ram_qw_indicator_toggle
    db "Quickwarp indicator", #$FF

cm_mainmenu_toggle_oob:
    dw !CM_ACTION_TOGGLE_BYTE
    dl !lowram_oob_toggle
    db "OoB mode", #$FF

cm_mainmenu_toggle_lit_rooms:
    dw !CM_ACTION_TOGGLE_BYTE
    dl !ram_lit_rooms_toggle
    db "Lit rooms", #$FF


tezt:
    LDA.b #$01 : STA !ram_xy_toggle
    RTS

cm_hud_table:
    incbin cm_gfx.bin;
