#MIPS Interactive Tic-Tac-Toe Game
#bitmap display settings: 8x8 pixels 512x512 display base address 0x10008000($gp)
#keyboard and display MMIO: control - 0xffff0000m data = 0xffff0004
#Controls: H or h to hit S or s to Stand

.data 
#card deck: 52 bytes to represent card values (1..13: 1=A 11=J, 12=Q, 13=K)
deck: .space 52
deck_ptr: .word 0 #index of next card to draw

player_hand: .space 12 #up to 12 card for player
dealer_hand: .space 12 #up to 12 card for dealer
player_count: .word 0 #num card in player hand
dealer_count: .word 0 #num card in dealer hand

#display colors 
COLOR_BG: .word 0x001B4D3E #felt green
COLOR_CARD_BG: .word 0x00FFFFFF #pure white
COLOR_CARD_BORDER: .word 0x00000000 #black border
COLOR_RED_SUIT: .word 0x00E74C3C #red marker
COLOR_BLK_SUIT: .word 0x002C3E50 #dark marker

#terminal messages
startMsg: .asciiz "BLACKJACK\n"
instructions: .asciiz "Controls:\n Press 'H' to hit\n Press 'S' to stand\n\n "
playerScoreMsg: .asciiz "Player total: "
dealerScoreMsg: .asciiz "Dealer total: "
playerBustMsg: .asciiz "Player Busts Dealer Wins\n"
dealerBustMsg: .asciiz "Dealer Busts PLayer Wins\n"
playerWinMsg: .asciiz "Player Wins\n"
dealerWinMsg: .asciiz "Dealer Wins\n"
pushMsg: .asciiz "Its a Tie\n"
promptMsg: .asciiz "\nChoose action [H = Hit / S = Stand]: "
newline: .asciiz "\n"

.text
.globl main

#main control flow
main:
	#print welcome banner
	li $v0, 4
	la $a0, startMsg
	syscall 
	la $a0 instructions 
	syscall
	
	#initalize display graphics
	jal clear_screen
	
	#initalize and shuffle deck
	jal init_deck
	jal shuffle_deck
	sw $0, deck_ptr
	
	# Reset hand counters
    	sw   $0, player_count
    	sw   $0, dealer_count
	
	#inital deal: Player (2 cards), Dealer (2 cards)
	jal  deal_player_card
	jal  deal_dealer_card
	jal  deal_player_card
	jal  deal_dealer_card
	
	#refresh visual table layout
	jal redraw_table
	
player_turn:
	#calcuate player total score
	la $a0, player_hand
	lw $a1, player_count
	jal calc_score
	move $s0, $v0 #$s0 = player score
	
	#print player status to console
	li $v0, 4
	la $a0, playerScoreMsg
	syscall
	li $v0, 1
	move $a0, $s0
	syscall
	li $v0, 4
	la $a0, newline
	syscall 
	
	#bust check (>21)
	li $t0, 21
	bgt $s0, $t0, player_busted

	#Solicit player decision ('H' or 'S') via MMIO
	li $v0, 4
	la $a0, promptMsg
	syscall
	jal get_hs_input # returen h or s in $v0
	
	beq $v0, 's', dealer_turn # stand -> jump to dealer
	
	#hit -> deal card to player
	jal deal_player_card
	jal redraw_table
	j player_turn
	
player_busted:
	li $v0, 4
	la $a0, playerBustMsg
	syscall
	j exit_game
	
dealer_turn:
	#calcuate dealer total score
	la $a0, dealer_hand
	lw $a1, dealer_count
	jal calc_score
	move $s1, $v0 # $s1 = dealer score
	
	#print dealer status to console
	li $v0, 4
	la $a0, dealerScoreMsg
	syscall
	li $v0, 1
	move $a0, $s1
	syscall
	li $v0, 4
	la $a0, newline
	syscall 
	
	#dealer hits soft 16, stands on 17+
	li $t0, 17
	bge $s1, $t0, evaluate_winner

	#deal card to dealer and loop
	jal deal_dealer_card
	jal redraw_table
	j dealer_turn

evaluate_winner: 
	li $t0, 21
	bgt $s1, $t0, dealer_busted
	
	#compare player to dealer
	bgt $s0, $s1, player_wins
	blt $s0, $s1, dealer_wins
	
	#equal totals -> tie
	li $v0, 4
	la $a0, pushMsg
	syscall
	j exit_game
	
dealer_busted:
	li $v0, 4
	la $a0, dealerBustMsg
	syscall
	j exit_game
	
player_wins:
	li $v0, 4
	la $a0, playerWinMsg
	syscall
	j exit_game
	
dealer_wins:
	li $v0, 4
	la $a0,dealerWinMsg
	syscall
	j exit_game
	
exit_game:
	li $v0, 10
	syscall
	
# Input Handling Procedure: get_hs_input
# Accepts 'H', 'h', 'S', or 's' via Keyboard MMIO
# Output: $v0 = ASCII lowercase character ('h' or 's')
get_hs_input:
	li $t0, 0xffff0000
poll_key:
	lw $t1, 0($t0)
	andi $t1, $t1, 1
	beqz $t1, poll_key
	
	lw $t2, 4($t0) #read ascii char
	
	#convert uppercase to lowercase if needed
	li $t3, 'A'
	blt $t2, $t3, check_lower
	li $t3, 'Z'
	bgt $t2, $t3, check_lower
	addi $t2, $t2, 32 #to lowercase
	
check_lower:
	beq $t2, 'h', valid_key
	beq $t2, 's', valid_key
	j poll_key
	
valid_key:
	move $v0, $t2
	jr $ra
	
#deck initailization & shuffle
init_deck: 
	la $t0, deck
	li $t1, 0 #counter 0..51
id_loop:
	beq $t1, 52, id_done
	#card value = (index % 13) + 1
	li $t2, 13
	div $t1, $t2
	mfhi $t3
	addi $t3, $t3, 1
	sb $t3, 0($t0)
	addi $t0, $t0, 1
	addi $t1, $t1, 1
	j id_loop
id_done:
	jr $ra

shuffle_deck:
	addi $sp, $sp, -12
	sw $ra, 8($sp)
	sw $s0, 4($sp)
	sw $s1, 0($sp)
	
	li $s0, 51  # $s0 = 1 from 51 down to 1
sf_loop:
	blez $s0, sf_done
	
	#generate psuedo-random index j in range [0,i] 
	li $v0, 42
	li $a0, 0
	addi $a1, $s0, 1 # upper bound exclusive = i + 1
	syscall # $a0 = random integer j
	
	move $s1, $a0 # $s1 =j
	
	#swap deck[i] and deck[j]
	la $t0, deck
	add $t1, $t0, $s0  #address deck[i]
	add $t2, $t0, $s1 # address deck[j]
	lbu $t3, 0($t1)
	lbu $t4, 0($t2)
	sb  $t4, 0($t1)
	sb  $t3, 0($t2)
	
	addi $s0, $s0, -1
	j sf_loop
	
sf_done:
	lw $s1, 0($sp)
	lw $s0, 4($sp)
	lw $ra, 8($sp)
	addi $sp, $sp, 12
	jr $ra
	
#card dealing subroutines
deal_player_card:
	lw $t0, deck_ptr
	la $t1, deck
	add $t1, $t1, $t0 # current card pointer
	lbu $t2, 0($t1)
	
	#store card in player hand 
	lw $t3, player_count
	la $t4, player_hand 
	add $t4, $t4, $t3
	sb $t2, 0($t4)
	
	#Increment state counters
	addi $t3, $t3, 1
	sw $t3, player_count 
	addi $t0, $t0, 1
	sw $t0, deck_ptr
	jr $ra

deal_dealer_card:
	lw $t0, deck_ptr
	la $t1, deck
	add $t1, $t1, $t0 # current card pointer
	lbu $t2, 0($t1)
	
	#store card in dealer hand 
	lw $t3, dealer_count
	la $t4, dealer_hand 
	add $t4, $t4, $t3
	sb $t2, 0($t4)
	
	#Increment state counters
	addi $t3, $t3, 1
	sw $t3, dealer_count 
	addi $t0, $t0, 1
	sw $t0, deck_ptr
	jr $ra	
	
# procedure: calc score
# $a0 = pointer to hand array $a1  = card count in hand
# output: $v0 = calculated optimal Blackjack score

calc_score:
	li $v0, 0 #score sum
	li $t0, 0 # ace counter
	li $t1, 0 #index

cs_loop:
	beq $t1, $a1, cs_adjust
	add $t2, $a0, $t1
	lbu $t3, 0($t2) #card value
	
	li $t4, 1
	beq $t3, $t4, count_ace
	
	li $t4, 10
	bge $t3, $t4, count_face # face cards (10,11,12,13) worth 10
	
	#number cards
	add $v0, $v0, $t3
	j cs_next
	
count_face:
	addi $v0, $v0, 10
	j cs_next
	
count_ace:
	addi $v0, $v0, 11 #ace initally = 11
	addi $t0, $t0, 1 #count aces

cs_next:
	addi $t1, $t1, 1
	j cs_loop
	
cs_adjust:
	#if total score > 21 and aces counted as 11, reduce by 10
	li $t4, 21
	ble $v0, $t4, cs_done
	blez $t0, cs_done
	addi $v0, $v0, -10
	addi $t0, $t0, -1
	j cs_adjust
	
cs_done:
	jr $ra
	
#graphics subroutines
# Helper Procedure: draw_pixel
# $a0 = X (0..63), $a1 = Y (0..63), $a2 = Color
draw_pixel:
    sll  $t8, $a1, 6
    add  $t8, $t8, $a0
    sll  $t8, $t8, 2
    lui  $t9, 0x1000
    ori  $t9, $t9, 0x8000
    add  $t8, $t8, $t9
    sw   $a2, 0($t8)
    jr   $ra

clear_screen:
    addi $sp, $sp, -4
    sw   $ra, 0($sp)
    lw   $a2, COLOR_BG
    li   $a1, 0
cls_y:
    beq  $a1, 64, cls_done
    li   $a0, 0
cls_x:
    beq  $a0, 64, cls_next_y
    jal  draw_pixel
    addi $a0, $a0, 1
    j    cls_x
cls_next_y:
    addi $a1, $a1, 1
    j    cls_y
cls_done:
    lw   $ra, 0($sp)
    addi $sp, $sp, 4
    jr   $ra

# Helper Procedure: draw_rect
# $a0 = Start X, $a1 = Start Y, $a2 = Width, $a3 = Height, stack(0) = Color
draw_rect:
    addi $sp, $sp, -20
    sw   $ra, 16($sp)
    sw   $s0, 12($sp)
    sw   $s1, 8($sp)
    sw   $s2, 4($sp)
    sw   $s3, 0($sp)

    move $s0, $a0                # X
    move $s1, $a1                # Y
    move $s2, $a2                # Width
    move $s3, $a3                # Height
    lw   $a2, 20($sp)            # Color arg from caller stack

    li   $t1, 0                  # dy
dr_y:
    beq  $t1, $s3, dr_done
    li   $t0, 0                  # dx
dr_x:
    beq  $t0, $s2, dr_next_y
    add  $a0, $s0, $t0
    add  $a1, $s1, $t1
    jal  draw_pixel
    addi $t0, $t0, 1
    j    dr_x
dr_next_y:
    addi $t1, $t1, 1
    j    dr_y
dr_done:
    lw   $s3, 0($sp)
    lw   $s2, 4($sp)
    lw   $s1, 8($sp)
    lw   $s0, 12($sp)
    lw   $ra, 16($sp)
    addi $sp, $sp, 20
    jr   $ra

# Render a single card visual representation
# $a0 = Base X, $a1 = Base Y, $a2 = Card Value (1..13)
draw_card:
    addi $sp, $sp, -20
    sw   $ra, 16($sp)
    sw   $s0, 12($sp)
    sw   $s1, 8($sp)
    sw   $s2, 4($sp)
    sw   $s3, 0($sp)

    move $s0, $a0
    move $s1, $a1
    move $s2, $a2

    # Draw card black border rectangle (Width = 8, Height = 11)
    lw   $t0, COLOR_CARD_BORDER
    addi $sp, $sp, -4
    sw   $t0, 0($sp)
    li   $a2, 8
    li   $a3, 11
    jal  draw_rect
    addi $sp, $sp, 4
    
    # Draw card inner white rectangle (Width = 6, Height = 9)
    lw   $t0, COLOR_CARD_BG
    addi $sp, $sp, -4
    sw   $t0, 0($sp)
    addi $a0, $s0, 1
    addi $a1, $s1, 1
    li   $a2, 6
    li   $a3, 9
    jal  draw_rect
    addi $sp, $sp, 4
    
    # Draw suit indicator dot inside card
    # Red marker for Face/Ace, Blue/Black for numeric cards
    li   $t0, 10
    bge  $s2, $t0, red_suit
    li   $t0, 1
    beq  $s2, $t0, red_suit
    lw   $a2, COLOR_BLK_SUIT
    j    paint_suit
red_suit:
    lw   $a2, COLOR_RED_SUIT
paint_suit:
    addi $a0, $s0, 3
    addi $a1, $s1, 4
    jal  draw_pixel
    addi $a0, $s0, 4
    jal  draw_pixel

    lw   $s3, 0($sp)
    lw   $s2, 4($sp)
    lw   $s1, 8($sp)
    lw   $s0, 12($sp)
    lw   $ra, 16($sp)
    addi $sp, $sp, 20
    jr   $ra

# Redraw entire visual table (Dealer hand top row, Player hand bottom row)
redraw_table:
    addi $sp, $sp, -20
    sw   $ra, 16($sp)
    sw   $s0, 12($sp)
    sw   $s1, 8($sp)
    sw   $s2, 4($sp)
    sw   $s3, 0($sp)

    jal  clear_screen

    # Draw Dealer Cards (Y = 6)
    lw   $s0, dealer_count
    li   $s1, 0                  # Index counter
    la   $s2, dealer_hand
draw_dealer_loop:
    beq  $s1, $s0, draw_player_prep
    mul  $a0, $s1, 10
    addi $a0, $a0, 4             # X spacing
    li   $a1, 6                  # Y offset
    add  $t0, $s2, $s1
    lbu  $a2, 0($t0)             # Card value
    jal  draw_card
    addi $s1, $s1, 1
    j    draw_dealer_loop

draw_player_prep:
    # Draw Player Cards (Y = 40)
    lw   $s0, player_count
    li   $s1, 0
    la   $s2, player_hand
draw_player_loop:
    beq  $s1, $s0, redraw_done
    mul  $a0, $s1, 10
    addi $a0, $a0, 4             # X spacing
    li   $a1, 40                 # Y offset
    add  $t0, $s2, $s1
    lbu  $a2, 0($t0)             # Card value
    jal  draw_card
    addi $s1, $s1, 1
    j    draw_player_loop

redraw_done:
    lw   $s3, 0($sp)
    lw   $s2, 4($sp)
    lw   $s1, 8($sp)
    lw   $s0, 12($sp)
    lw   $ra, 16($sp)
    addi $sp, $sp, 20
    jr   $ra