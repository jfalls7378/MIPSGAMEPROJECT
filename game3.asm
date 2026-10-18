#this will be..connect 4....tictactoe works this theorectially is that adjusted
#MIPS Interactive Connect 4 Game
#bitmap display settings: 8x8 pixels 512x512 display base address 0x10008000($gp)
#keyboard and display MMIO: control - 0xffff0000m data = 0xffff0004
#69 ways to win 24 horizontal, 21 vertical, 24 diagona;
.data
#board state: 42 bytes (7 cols x 6 rows) row-major order
#0 = empty, 1 = Player 1 yellow, 2 = Player 2 red
board: .space 42 #42 cells (7 cols x 6 rows)

#display colors (0x00RRGGBB format)
COLOR_BG: .word 0x001B263B #dark navy background
COLOR_BOARD: .word 0x00415A77 #board blue frame
COLOR_SLOT: .word 0x000D1B2A #empty slot dark circle
COLOR_P1: .word 0x00F1C40F #p1 yellow
COLOR_P2: .word 0x00E74C3C #p2 red

#Terminal messaging
startMsg: .asciiz "Connect 4\n"
instructions: .asciiz "Use keys 0-6 to choose a column:\n[ 0 ][ 1 ][ 2 ][ 3 ][ 4 ][ 5 ][ 6 ]\n\n"
turnP1Msg: .asciiz "\nPlayer 1's turn (Yellow Keys 0-6): "
turnP2Msg: .asciiz "\nPLayer 2's turn (Red Keys 0-6): "
invalidMsg: .asciiz "Invalid key or full column! Try again.\n"
winP1Msg: .asciiz "\n*** PLAYER 1 WINS ***\n"
winP2Msg: .asciiz "\n*** PLAYER 2 WINS ***\n"
drawMsg:.asciiz "\n*** GAME IS A DRAW ***\n"

.text
.globl main

#main program loop
main:
	#print welcome instructions to console
	li $v0, 4
	la $a0, startMsg
	syscall 
	la $a0 instructions 
	syscall
	
	#initialize board memory to zeros
	la $t0, board
	li $t1, 0
clear_board_mem:	
	beq  $t1, 42, board_mem_ready
        sb   $zero, 0($t0)
        addi $t0, $t0, 1
        addi $t1, $t1, 1
        j    clear_board_mem

board_mem_ready:	
	#clear screen and draw inital empty board
	jal clear_screen
	jal draw_board_frame
	
	#state variables: $s0 = current player (1 or 2) , $s1 = total moves
	li $s0, 1
	li $s1, 0 
	
game_loop:
	beq $s1, 42, handle_draw #9 turns no winner -> draw
	
	#prompt turn message 
	li $v0, 4
	beq $s0, 1, prompt_p1
	la $a0, turnP2Msg
	j print_prompt
prompt_p1:
	la $a0, turnP1Msg
print_prompt:
	syscall
	
	#read user input 
	jal get_column_input #returns column index (0..6) in $v0
	
	#attempt to drop piece into chose column
	move $a0, $v0 #column
	move $a1, $s0 #player id
	jal drop_piece #returns row index in $v0 or -1 if full
	
	bltz $v0, invalid_move #column full -> reject
	
	move  $s2, $v0 # $s2 = row token landed
	
	#create marker on Bitmap display
	#$a0 = column(already set), $a1 = row ($s2) $a2 = player 
	move $a1, $s2 
	move $a2, $s0 
	jal draw_token
	
	#increment move counter
	addi $s1, $s1, 1
	
	#check winning condiitions
	jal check_win #return winner (0, 1, 2) in $v0
	bne $v0, $zero, handle_win
	
	#switch current player (1 -> 2, 2 -> 1)
	li $t0, 3
	sub $s0, $t0, $s0
	j game_loop
	
invalid_move:
	li $v0, 4
	la $a0, invalidMsg
	syscall
	j game_loop

handle_win:
	li $v0, 4
	beq $s0, 1, win_p1_msg
	la $a0, winP2Msg
	j print_win
win_p1_msg:
	la $a0, winP1Msg
print_win:
	syscall
	j exit_game
	
handle_draw:
	li $v0, 4
	la $a0, drawMsg
	syscall
	
exit_game:
	li $v0, 10 # exit program syscall
	syscall
	
#procedure: get column input, MMIO key press reading with key range validation ASCII to int (0-6), output: $v0 = cell index (0 to 6)
get_column_input:
	li $t0, 0xffff0000 #keyboard control register address
poll_keyboard:
	lw $t1, 0($t0) # read control register status
	andi $t1, $t1, 1 # mask bit 0 (1 = key ready)
	beqz $t1, poll_keyboard # loop until key pressed
	lw $t2, 4($t0) # read ascii char from data register
	#convert ascii char to numeric cell index ('0' = 48 ascii)
	addi $v0, $t2, -48
	bltz $v0, poll_keyboard #ignore keys less than 0
	li $t3, 6
	bgt $v0, $t3, poll_keyboard # ignore keys greater than 8
	jr $ra
	
#procedure: drop piece, find lowest avaliable row in column $a0 and updates board array, input $a0 = column, $a1 = player id ooutput $v0 = row token landed or -1 if column full
drop_piece: 
	li $t0, 5 #start scan at bottom row
drop_scan:
	bltz $t0, col_is_full # row < 0 -> column is full
	
	#index = (row * 7) +col
	mul $t1, $t0, 7
	add $t1, $t1, $a0
	la $t2, board
	add $t2, $t2, $t1
	
	lbu $t3, 0($t2)
	beqz $t3, empty_slot_found #cell value 0 = empty
	
	addi $t0, $t0, -1 # move up 1 row
	j drop_scan
	
empty_slot_found:
	sb $a1, 0($t2) #player id to board
	move $v0, $t0 #return row index
	jr $ra
	
col_is_full:
	li $v0, -1
	jr $ra
	
#procedure: check win, check horizontal, vertical, diagonal left & right lines, output: $v0 = winner id , 0 = no win 1(p1wins), 2(p2wins)
check_win:
	addi $sp, $sp, -20
    sw   $ra, 16($sp)
    sw   $s0, 12($sp)
    sw   $s1, 8($sp)
    sw   $s2, 4($sp)
    sw   $s3, 0($sp)

    la   $s0, board

    # 1. Horizontal Check (Rows 0..5, Cols 0..3)
    li   $s1, 0                  # Row
chk_h_row:
    beq  $s1, 6, prep_v_check
    li   $s2, 0                  # Col
chk_h_col:
    beq  $s2, 4, next_h_row
    mul  $a0, $s1, 7
    add  $a0, $a0, $s2           # Start index
    li   $a1, 1                  # Stride = +1
    jal  eval_line
    bne  $v0, $zero, win_detected
    addi $s2, $s2, 1
    j    chk_h_col
next_h_row:
    addi $s1, $s1, 1
    j    chk_h_row

prep_v_check:
    # 2. Vertical Check (Rows 0..2, Cols 0..6)
    li   $s1, 0                  # Row
chk_v_row:
    beq  $s1, 3, prep_dr_check
    li   $s2, 0                  # Col
chk_v_col:
    beq  $s2, 7, next_v_row
    mul  $a0, $s1, 7
    add  $a0, $a0, $s2           # Start index
    li   $a1, 7                  # Stride = +7
    jal  eval_line
    bne  $v0, $zero, win_detected
    addi $s2, $s2, 1
    j    chk_v_col
next_v_row:
    addi $s1, $s1, 1
    j    chk_v_row

prep_dr_check:
    # 3. Diagonal Right Check / (Rows 0..2, Cols 0..3)
    li   $s1, 0                  # Row
chk_dr_row:
    beq  $s1, 3, prep_dl_check
    li   $s2, 0                  # Col
chk_dr_col:
    beq  $s2, 4, next_dr_row
    mul  $a0, $s1, 7
    add  $a0, $a0, $s2           # Start index
    li   $a1, 8                  # Stride = +8 (+1 row, +1 col)
    jal  eval_line
    bne  $v0, $zero, win_detected
    addi $s2, $s2, 1
    j    chk_dr_col
next_dr_row:
    addi $s1, $s1, 1
    j    chk_dr_row

prep_dl_check:
    # 4. Diagonal Left Check \ (Rows 0..2, Cols 3..6)
    li   $s1, 0                  # Row
chk_dl_row:
    beq  $s1, 3, no_win_found
    li   $s2, 3                  # Col starting at 3
chk_dl_col:
    beq  $s2, 7, next_dl_row
    mul  $a0, $s1, 7
    add  $a0, $a0, $s2           # Start index
    li   $a1, 6                  # Stride = +6 (+1 row, -1 col)
    jal  eval_line
    bne  $v0, $zero, win_detected
    addi $s2, $s2, 1
    j    chk_dl_col
next_dl_row:
    addi $s1, $s1, 1
    j    chk_dl_row

no_win_found:
    li   $v0, 0
win_detected:
    lw   $s3, 0($sp)
    lw   $s2, 4($sp)
    lw   $s1, 8($sp)
    lw   $s0, 12($sp)
    lw   $ra, 16($sp)
    addi $sp, $sp, 20
    jr   $ra

#helper procedure: eval_line
#check 4 consecuritive array locations starting at $a0 with offset $a1, output $v0 = player id if 4 in row match or 0
eval_line:
	la $t0, board
	add $t0, $t0, $a0
	lbu $t1, 0($t0) #first cell value
	beqz $t1, line_no_match # empty cell -> skip
	li $t2, 1
line_loop:
	beq $t2, 4, line_match
	add $t0, $t0, $a1 #offset
	lbu $t3, 0($t0)
	bne $t1, $t3, line_no_match
	addi $t2, $t2, 1
	j line_loop
	
line_match:
	move $v0, $t1 #return winning player
	jr $ra

line_no_match:
	li $v0, 0
	jr $ra
#graphics subroutines(bitmap display)
	
#helper procedure: draw pixel
# $a0 = X coordinate (0..63)  $a1 = Y coordinate (0..63)   $a2 = color value
draw_pixel:
	#memory offest = 0x10008000 + 4 * (Y * 64 + X)
	sll  $t8, $a1, 6             # Y * 64
    	add  $t8, $t8, $a0           # Y * 64 + X
    	sll  $t8, $t8, 2             # Convert to byte offset (* 4)
    	lui  $t9, 0x1000             # Base address 0x10008000
    	ori  $t9, $t9, 0x8000
    	add  $t8, $t8, $t9
    	sw   $a2, 0($t8)             # Write pixel color to display address
    	jr   $ra

#procedure: clear screen fills screen grid (64x64) with bg color
clear_screen:
    addi $sp, $sp, -4
    sw   $ra, 0($sp)
    lw   $a2, COLOR_BG
    li   $a1, 0                  # Y counter
cs_y_loop:
    beq  $a1, 64, cs_done
    li   $a0, 0                  # X counter
cs_x_loop:
    beq  $a0, 64, cs_next_y
    jal  draw_pixel
    addi $a0, $a0, 1
    j    cs_x_loop
cs_next_y:
    addi $a1, $a1, 1
    j    cs_y_loop
cs_done:
    lw   $ra, 0($sp)
    addi $sp, $sp, 4
    jr   $ra

# Helper Procedure: draw_fill_rect
# $a0 = Start X, $a1 = Start Y, $a2 = Width, $a3 = Height, stack(0) = Color
draw_fill_rect:
    addi $sp, $sp, -20
    sw   $ra, 16($sp)
    sw   $s0, 12($sp)
    sw   $s1, 8($sp)
    sw   $s2, 4($sp)
    sw   $s3, 0($sp)

    move $s0, $a0
    move $s1, $a1
    move $s2, $a2
    move $s3, $a3
    lw   $a2, 20($sp)

    li   $t1, 0
fr_y:
    beq  $t1, $s3, fr_done
    li   $t0, 0
fr_x:
    beq  $t0, $s2, fr_next_y
    add  $a0, $s0, $t0
    add  $a1, $s1, $t1
    jal  draw_pixel
    addi $t0, $t0, 1
    j    fr_x
fr_next_y:
    addi $t1, $t1, 1
    j    fr_y
fr_done:
    lw   $s3, 0($sp)
    lw   $s2, 4($sp)
    lw   $s1, 8($sp)
    lw   $s0, 12($sp)
    lw   $ra, 16($sp)
    addi $sp, $sp, 20
    jr   $ra

# Draws the Connect Four blue grid frame with dark circle slots
draw_board_frame:
    addi $sp, $sp, -12
    sw   $ra, 8($sp)
    sw   $s0, 4($sp)
    sw   $s1, 0($sp)

    # Draw solid blue backing board rect (X: 1..62, Y: 8..63)
    lw   $t0, COLOR_BOARD
    addi $sp, $sp, -4
    sw   $t0, 0($sp)
    li   $a0, 1
    li   $a1, 8
    li   $a2, 62
    li   $a3, 55
    jal  draw_fill_rect
    addi $sp, $sp, 4

    # Draw empty slots (6 rows x 7 cols)
    li   $s0, 0                  # Row (0..5)
frame_r_loop:
    beq  $s0, 6, frame_done
    li   $s1, 0                  # Col (0..6)
frame_c_loop:
    beq  $s1, 7, frame_next_r

    # Draw empty slot (COLOR_SLOT)
    move $a0, $s1
    move $a1, $s0
    li   $a2, 0                  # 0 = Slot background
    jal  draw_token

    addi $s1, $s1, 1
    j    frame_c_loop
frame_next_r:
    addi $s0, $s0, 1
    j    frame_r_loop

frame_done:
    lw   $s1, 0($sp)
    lw   $s0, 4($sp)
    lw   $ra, 8($sp)
    addi $sp, $sp, 12
    jr   $ra

# Procedure: draw_token
# Input: $a0 = Column (0..6), $a1 = Row (0..5), $a2 = Type (0 = Slot, 1 = P1, 2 = P2)
draw_token:
    addi $sp, $sp, -20
    sw   $ra, 16($sp)
    sw   $s0, 12($sp)
    sw   $s1, 8($sp)
    sw   $s2, 4($sp)
    sw   $s3, 0($sp)

    # Map Column to X: Base = col * 8 + 4
    mul  $s0, $a0, 8
    addi $s0, $s0, 4

    # Map Row to Y: Base = row * 8 + 11
    mul  $s1, $a1, 8
    addi $s1, $s1, 11

    # Select color based on $a2 parameter
    beqz $a2, col_slot
    li   $t0, 1
    beq  $a2, $t0, col_p1
    lw   $s2, COLOR_P2
    j    render_circle
col_slot:
    lw   $s2, COLOR_SLOT
    j    render_circle
col_p1:
    lw   $s2, COLOR_P1

render_circle:
    # Render a 6x6 pixel circle token shape inside the cell
    addi $sp, $sp, -4
    sw   $s2, 0($sp)             # Color argument
    addi $a0, $s0, 1
    move $a1, $s1
    li   $a2, 4
    li   $a3, 6
    jal  draw_fill_rect
    addi $sp, $sp, 4	

    addi $sp, $sp, -4
    sw   $s2, 0($sp)
    move $a0, $s0
    addi $a1, $s1, 1
    li   $a2, 6
    li   $a3, 4
    jal  draw_fill_rect
    addi $sp, $sp, 4
    
    lw   $s3, 0($sp)
    lw   $s2, 4($sp)
    lw   $s1, 8($sp)
    lw   $s0, 12($sp)
    lw   $ra, 16($sp)
    addi $sp, $sp, 20
    jr   $ra