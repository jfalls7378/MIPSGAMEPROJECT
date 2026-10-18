#MIPS Interactive Tic-Tac-Toe Game
#bitmap display settings: 8x8 pixels 512x512 display base address 0x10008000($gp)
#keyboard and display MMIO: control - 0xffff0000m data = 0xffff0004

.data
#game state: 9 bytes representing 0..8
#0 = empty, 1 = Player X, 2 = Player O
board: .byte 0, 0, 0, 0, 0, 0, 0, 0, 0

#winning index patterns (8 lines * 3 bytes = 24 bytes)
win_patterns: 
	.byte 0,1,2 3,4,5 6,7,8 #horizontal
	.byte 0,3,6 1,4,7 2,5,8 #vertical
	.byte 0,4,8 2,4,6 #diagonal

#display colors (0x00RRGGBB format)
COLOR_BG: .word 0x01E12E #dark slate
COLOR_GRID: .word 0x00CDD6F4 #off white
COLOR_X: .word 0x00F38BA8 #pink/red
COLOR_O: .word 0x0089B4FA #blue

#Terminal messaging
startMsg: .asciiz "TICTACTOE\n"
instructions: .asciiz "Use keys 0-8 to place your maker:\n 0 | 1 | 2 \n---+---+---\n 3 | 4 | 5 \n---+---+---\n 6 | 7 | 8 \n\n"
turnXMsg: .asciiz "\nPlayer X's turn (Key 0-8): "
turnOMsg: .asciiz "\nPLayer O's turn (Key 0-8)"
invalidMsg: .asciiz "Invalid key or occupied cell! Try again.\n"
winXMsg: .asciiz "\n*** PLAYER X WINS ***\n"
winOMsg: .asciiz "\n*** PLAYER O WINS ***\n"
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
	
	#clear screen draw grid
	jal clear_screen
	jal draw_grid
	
	#initialize game loop 
	li $s0, 1 # $s0 = current player(1 = X, 2 = O)
	li $s1, 0 # $s1 = turn counter (0 to 9)
	
game_loop:
	beq $s1, 9, handle_draw #9 turns no winner -> draw
	
	#prompt turn message 
	li $v0, 4
	beq $s0, 1, prompt_x
	la $a0, turnOMsg
	j print_prompt
prompt_x:
	la $a0, turnXMsg
print_prompt:
	syscall
	
	#read user input 
	jal get_user_input #returns cell index (0..8) in $v0
	
	#validate cell choice: board[index] must be 0
	la $t0, board
	add $t1, $t0, $v0 #address of board[index]
	lbu $t2, 0($t1)
	bne $t2, $0, invalid_move
	
	#record player move in board array
	sb $s0, 0($t1)
	
	#create marker on Bitmap display
	move $a0, $v0 #cell index (0..8)
	move $a1, $s0 #player 
	jal draw_marker
	
	#increment turn counter
	addi $s1, $s1, 1
	
	#check winning condiitions
	jal check_win #return winner (0 -> none, 1 -> X, 2 -> 0) in $v0
	bne $v0, $0, handle_win
	
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
	beq $s0, 1, win_x_msg
	la $a0, winOMsg
	j print_win
win_x_msg:
	la $a0, winXMsg
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
	
#procedure: get user input, MMIO key press reading with key range validation (0-8), output: $v0 = cell index (0 to 8)
get_user_input:
	li $t0, 0xffff0000 #keyboard control register address
poll_keyboard:
	lw $t1, 0($t0) # read control register status
	andi $t1, $t1, 1 # mask bit 0 (1 = key ready)
	beqz $t1, poll_keyboard # loop until key pressed
	lw $t2, 4($t0) # read ascii char from data register
	#convert ascii char to numeric cell index ('0' = 48 ascii)
	addi $v0, $t2, -48
	bltz $v0, poll_keyboard #ignore keys less than 0
	li $t3, 8
	bgt $v0, $t3, poll_keyboard # ignore keys greater than 8
	jr $ra
	
#procedure: check win, scan 8 possible winning combonations in win_patterns, output: $v0 = no win, 1(X wins), 2(O wins)
check_win:
	la $t0, win_patterns
	la $t1, board
	li $t2, 0 #pattern index counter (0..7)

win_search_loop:
	beq $t2, 8, no_winner # checked all 8 patterns with no hit
	
	#load 3 cell offsets for current pattern
	lbu $t3, 0($t0)
	lbu $t4, 1($t0)
	lbu $t5, 2($t0)
	
	#get values from board array
	add $t6, $t1, $t3
	lbu $t3, 0($t6) #val a 
	beqz $t3, next_pattern # empty cell -> pattern cant win
	
	add $t6, $t1, $t4
	lbu $t4, 0($t6) #val b
	bne $t3, $t4, next_pattern # val a != val b
	
	add $t6, $t1, $t5
	lbu $t5, 0($t6) #val a 
	bne $t3, $t5, next_pattern # val a != val b
	
	#mathc found! return winning player id
	move $v0, $t3
	jr  $ra
	
next_pattern:
	addi $t0, $t0, 3 # move to next 3-byte combo
	addi $t2, $t2, 1 #increment pattern index
	j win_search_loop
	
no_winner:
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

# Procedure: draw_grid
# Draws vertical and horizontal grid dividing lines on bitmap display
draw_grid:
    addi $sp, $sp, -4
    sw   $ra, 0($sp)

    lw   $a2, COLOR_GRID

    # Draw Vertical Lines at X = 21 and X = 42
    li   $a1, 0
dg_v_loop:
    beq  $a1, 64, dg_h_prep
    li   $a0, 21
    jal  draw_pixel
    li   $a0, 42
    jal  draw_pixel
    addi $a1, $a1, 1
    j    dg_v_loop

dg_h_prep:
    # Draw Horizontal Lines at Y = 21 and Y = 42
    li   $a0, 0
dg_h_loop:
    beq  $a0, 64, dg_done
    li   $a1, 21
    jal  draw_pixel
    li   $a1, 42
    jal  draw_pixel
    addi $a0, $a0, 1
    j    dg_h_loop

dg_done:
    lw   $ra, 0($sp)
    addi $sp, $sp, 4
    jr   $ra

# Procedure: draw_marker
# $a0 = cell index (0..8)
# $a1 = player marker type (1 = X, 2 = O)
draw_marker:
    addi $sp, $sp, -16
    sw   $ra, 12($sp)
    sw   $s0, 8($sp)
    sw   $s1, 4($sp)
    sw   $s2, 0($sp)

    move $s0, $a0
    move $s1, $a1

    # Map cell index to base cell coordinate (top-left X, Y)
    # Row = index / 3; Col = index % 3
    li   $t0, 3
    div  $s0, $t0
    mflo $t1                    # Row (0..2)
    mfhi $t2                    # Col (0..2)

    # Base X = Col * 21 + 4
    mul  $s2, $t2, 21
    addi $s2, $s2, 4            # Cell start X

    # Base Y = Row * 21 + 4
    mul  $s0, $t1, 21
    addi $s0, $s0, 4            # Cell start Y

    beq  $s1, 1, render_x

    # Render 'O' Marker (14x14 Hollow Box)
    lw   $a2, COLOR_O
    li   $t0, 0                 # Step index (0..13)
draw_o_loop:
    beq  $t0, 14, marker_done

    # Top/Bottom borders
    add  $a0, $s2, $t0
    move $a1, $s0
    jal  draw_pixel             # Top edge
    add  $a1, $s0, 13
    jal  draw_pixel             # Bottom edge

    # Left/Right borders
    move $a0, $s2
    add  $a1, $s0, $t0
    jal  draw_pixel             # Left edge
    add  $a0, $s2, 13
    jal  draw_pixel             # Right edge

    addi $t0, $t0, 1
    j    draw_o_loop

render_x:
    # Render 'X' Marker (Diagonal Cross)
    lw   $a2, COLOR_X
    li   $t0, 0                 # Step index (0..13)
draw_x_loop:
    beq  $t0, 14, marker_done

    # Top-left to bottom-right diagonal
    add  $a0, $s2, $t0
    add  $a1, $s0, $t0
    jal  draw_pixel

    # Bottom-left to top-right diagonal
    add  $a0, $s2, $t0
    sub  $a1, $s0, $t0
    addi $a1, $a1, 13
    jal  draw_pixel

    addi $t0, $t0, 1
    j    draw_x_loop

marker_done:
    lw   $s2, 0($sp)
    lw   $s1, 4($sp)
    lw   $s0, 8($sp)
    lw   $ra, 12($sp)
    addi $sp, $sp, 16
    jr   $ra
	






