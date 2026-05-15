; You may customize this and other start-up templates; 
; The location of this template is c:\emu8086\inc\0_com_template.txt

.model small
.stack 100h

; memory constants (fixed stuff)
VRAM_SEGMENT    EQU 0B800h
SCREEN_WIDTH    EQU 160     
BOTTOM_ROW      EQU 3840    

MAX_MEMORY_ITEMS EQU 15     ; max capacity for the array just in case
SPAWN_RATE       EQU 6     ; how fast objects drop

; macro to print strings without writing the same 3 lines over and over
PRINT_STR MACRO string_ptr
    mov dx, offset string_ptr
    mov ah, 09h
    int 21h
ENDM

; macro to move cursor around the grid
POSITION_CURSOR MACRO row, col
    mov ah, 02h
    mov bh, 0
    mov dh, row
    mov dl, col
    int 10h
ENDM

.data
    active_items         dw 3       ; number of falling objects
    paddle_width         dw 5       ; keep this odd so it looks centered
    
    L_WALL               dw 25      
    R_WALL               dw 55      
    
    CHAR_PADDLE_BLOCK    db '='     
    FALLING_OBJECT_SHAPE db 03h     ; falling object shape
    CHAR_BORDER          db 0BAh    
    
    COL_PADDLE           db 0Eh     ; colors
    COL_ITEM             db 0Ch     
    COL_BORDER           db 09h    
    
    score_row            db 0       
    score_col            db 0       
    COL_SCORE            db 0Fh     
    
    lives_row            db 1       ; y position of lives
    lives_col            db 0      ; x position of lives
    COL_LIVES            db 0Ah     ; bright green text to make it pop!
    
    game_speed           dw 0       
    

    msg_title_game       db '=== GRAVITY ZERO ===$'
    msg_title            db '--- CATCH THE FALLING OBJECTS ---$'
    msg_btn_start        db '[ START ]$'
    msg_btn_quit         db '[ QUIT ]$'
    msg_score            db 'Score: $'
    msg_lives            db 'Lives: $'
    msg_fail             db 'GAME OVER! Final Score: $'
    msg_retry            db 'Click Anywhere to Return to Menu$'

    score                dw 0
    lives                dw 3      
    player_pos           dw 3920    ; start at bottom middle
    old_player           dw 3920
    
    item_pos             dw MAX_MEMORY_ITEMS dup(4000) ; 4000 means off screen
    old_item_pos         dw MAX_MEMORY_ITEMS dup(4000)
    spawn_timer          dw 0
    random_seed          dw 0ABCDh

.code
start:
    mov ax, @data
    mov ds, ax
    mov ax, VRAM_SEGMENT
    mov es, ax

; drawing the main menu
show_menu:
    call clear_screen
    
    POSITION_CURSOR 6, 30
    PRINT_STR msg_title_game
    
    POSITION_CURSOR 8, 24
    PRINT_STR msg_title

    POSITION_CURSOR 12, 35
    PRINT_STR msg_btn_start

    POSITION_CURSOR 14, 35
    PRINT_STR msg_btn_quit

    ; turn on the mouse
    mov ax, 0000h
    int 33h
    mov ax, 0001h
    int 33h

menu_wait:
    ; wait for left click
    mov ax, 0003h
    int 33h
    and bx, 1                  
    jz menu_wait               

    ; divide pixels by 8 to get grid row/col
    shr cx, 1
    shr cx, 1
    shr cx, 1                  
    
    shr dx, 1
    shr dx, 1
    shr dx, 1                  

    ; check if start button clicked
    cmp dx, 12
    jne check_quit_btn
    cmp cx, 35
    jl check_quit_btn
    cmp cx, 43
    jg check_quit_btn
    jmp start_clicked          

check_quit_btn:
    ; check if quit button clicked
    cmp dx, 14
    jne wait_release
    cmp cx, 35
    jl wait_release
    cmp cx, 42
    jg wait_release
    jmp exit_game              

wait_release:
    ; make sure they let go of the mouse button so it doesn't double click
    mov ax, 0003h
    int 33h
    and bx, 1
    jnz wait_release
    jmp menu_wait

start_clicked:
    mov ax, 0002h              ; hide mouse
    int 33h
    jmp init_game

; setup new game
init_game:
    call clear_screen

    mov score, 0
    mov lives, 3               ; reset lives back to 3
    mov player_pos, 3920
    mov old_player, 3920
    mov spawn_timer, 0         
    
    ; reset all items to 4000 (hidden)
    mov cx, MAX_MEMORY_ITEMS
    mov si, 0
reset_items:
    mov item_pos[si], 4000
    mov old_item_pos[si], 4000
    add si, 2
    loop reset_items

    call draw_borders

; main gameplay loop
game_loop:
    call update_score_ui
    
    mov ax, player_pos
    mov old_player, ax
    
    ; save where items were so we can erase them cleanly
    mov cx, active_items
    mov si, 0
save_items_loop:
    mov ax, item_pos[si]
    mov old_item_pos[si], ax
    add si, 2
    loop save_items_loop

    call handle_input
    
    ; spawn stuff timer
    dec spawn_timer
    jg update_positions
    mov spawn_timer, SPAWN_RATE
    call spawn_new_item
    
update_positions:
    call update_items
    call erase_old_sprites
    call draw_current_sprites
    
    ;call delay_frame   ; slows the game
    jmp game_loop      

; keyboard stuff
handle_input proc
    mov ah, 01h                
    int 16h
    jz end_input               

    mov ah, 00h                
    int 16h
    or al, 20h                 ; lowercase it just in case caps lock is on
    
    cmp al, 'a'
    je move_left
    cmp al, 'd'
    je move_right
    cmp al, 27                 ; esc key to quit fast
    je exit_game
    jmp end_input

move_left:
    mov bx, L_WALL
    shl bx, 1
    add bx, BOTTOM_ROW
    
    ; figure out where the left side of paddle is
    mov cx, paddle_width
    shr cx, 1
    shl cx, 1
    add bx, cx
    
    cmp player_pos, bx
    jbe end_input
    sub player_pos, 2
    jmp end_input

move_right:
    mov bx, R_WALL
    shl bx, 1
    add bx, BOTTOM_ROW
    
    ; figure out where the right side of paddle is
    mov cx, paddle_width
    shr cx, 1
    shl cx, 1
    sub bx, cx
    
    cmp player_pos, bx
    jae end_input
    add player_pos, 2

end_input:
    ret
handle_input endp

; move items and check collisions
update_items proc
    mov cx, active_items
    mov si, 0
item_update_loop:
    cmp item_pos[si], 4000
    jae next_item              ; skip hidden items

    add item_pos[si], SCREEN_WIDTH 

    ; big math part to check hitboxes
    mov bx, player_pos
    
    ; get leftmost block
    mov ax, paddle_width
    shr ax, 1
    shl ax, 1
    sub bx, ax
    
    mov ax, item_pos[si]
    
    push cx
    mov cx, paddle_width
check_hit_loop:
    cmp ax, bx
    je caught_item
    add bx, 2
    loop check_hit_loop
    pop cx

    ; check if it hit the floor
    cmp item_pos[si], 4000
    jae missed_item
    jmp next_item

caught_item:
    pop cx                     ; fix stack
    inc score
    mov item_pos[si], 4000     ; hide it
    jmp next_item

missed_item:
    dec lives                  ; lose a life!
    cmp lives, 0               ; out of lives?
    jle trigger_game_over
    mov item_pos[si], 4000     ; hide object so it can drop again
    jmp next_item

next_item:
    add si, 2
    loop item_update_loop
    ret

trigger_game_over:
    jmp game_over
update_items endp

; drop a new thing from the top
spawn_new_item proc
    mov cx, active_items
    mov si, 0
find_slot:
    cmp item_pos[si], 4000
    jae slot_found             
    add si, 2
    loop find_slot
    ret                        

slot_found:
    ; get random number from system clock
    mov ah, 00h
    int 1Ah                    
    add random_seed, dx
    mov ax, random_seed
    xor dx, dx
    
    mov bx, R_WALL
    sub bx, L_WALL
    inc bx                     
    
    div bx                     
    add dx, L_WALL             
    shl dx, 1                  
    mov item_pos[si], dx       
    ret
spawn_new_item endp

; graphics stuff
clear_screen proc
    ; clear standard
    mov ax, 0003h
    int 10h
    
    ; paint it with standard text color so it resets
    mov ax, 0600h
    mov bh, 0Fh
    mov cx, 0000h
    mov dx, 184Fh
    int 10h
    ret
clear_screen endp

erase_old_sprites proc
    ; erase paddle
    mov ax, 0720h              
    mov cx, paddle_width
    mov di, old_player
    
    mov dx, paddle_width
    shr dx, 1
    shl dx, 1
    sub di, dx
    
erase_paddle_loop:
    mov es:[di], ax
    add di, 2
    loop erase_paddle_loop

    ; erase items
    mov cx, active_items
    mov si, 0
erase_items_loop:
    mov di, old_item_pos[si]
    cmp di, 4000
    jae skip_erase
    mov es:[di], ax 
skip_erase:
    add si, 2
    loop erase_items_loop
    ret
erase_old_sprites endp

draw_current_sprites proc
    ; draw paddle
    mov ah, COL_PADDLE
    mov al, CHAR_PADDLE_BLOCK
    mov cx, paddle_width
    mov di, player_pos
    
    mov dx, paddle_width
    shr dx, 1
    shl dx, 1
    sub di, dx
    
draw_paddle_loop:
    mov es:[di], ax
    add di, 2
    loop draw_paddle_loop

    ; draw items
    mov ah, COL_ITEM
    mov al, FALLING_OBJECT_SHAPE
    mov cx, active_items
    mov si, 0
draw_items_loop:
    mov di, item_pos[si]
    cmp di, 4000
    jae skip_draw
    mov es:[di], ax
skip_draw:
    add si, 2
    loop draw_items_loop
    ret
draw_current_sprites endp

update_score_ui proc
    
    ; math: (row * 160) + (col * 2) + 1
    xor ax, ax
    mov al, score_row
    mov bx, 160
    mul bx                     ; ax = row * 160
    xor bx, bx
    mov bl, score_col
    shl bx, 1                  ; bx = col * 2
    add ax, bx
    inc ax                     ; +1 for color byte
    mov di, ax
    
    mov cx, 10                 ; length of score text area
    mov al, COL_SCORE
color_score_loop:
    mov es:[di], al
    add di, 2
    loop color_score_loop


    xor ax, ax
    mov al, lives_row
    mov bx, 160
    mul bx
    xor bx, bx
    mov bl, lives_col
    shl bx, 1
    add ax, bx
    inc ax
    mov di, ax
    
    mov cx, 10                 ; length of lives text area
    mov al, COL_LIVES
color_lives_loop:
    mov es:[di], al
    add di, 2
    loop color_lives_loop

    POSITION_CURSOR score_row, score_col
    PRINT_STR msg_score
    mov ax, score
    call print_number

    POSITION_CURSOR lives_row, lives_col
    PRINT_STR msg_lives        
    mov ax, lives              
    call print_number

    ret
update_score_ui endp

draw_borders proc
    mov di, 0
    mov cx, 25
draw_b_loop:
    mov ah, COL_BORDER
    mov al, CHAR_BORDER
    
    mov bx, L_WALL
    dec bx
    shl bx, 1
    mov es:[di+bx], ax
    
    mov bx, R_WALL
    inc bx
    shl bx, 1
    mov es:[di+bx], ax
    
    add di, SCREEN_WIDTH
    loop draw_b_loop
    ret
draw_borders endp

; pause frame so it's actually playable
delay_frame proc
    mov cx, 00h
    mov dx, game_speed
    mov ah, 86h                
    int 15h
    ret
delay_frame endp

; math to print actual numbers instead of ascii weirdness
print_number proc
    mov cx, 0
    mov bx, 10
extract_digits:
    mov dx, 0
    div bx
    push dx
    inc cx
    cmp ax, 0
    jne extract_digits
print_digits:
    pop dx
    add dl, '0'
    mov ah, 02h
    int 21h
    loop print_digits
    ret
print_number endp

; end screens
game_over:
    call clear_screen

    POSITION_CURSOR 10, 26
    PRINT_STR msg_fail
    mov ax, score
    call print_number
    
    POSITION_CURSOR 14, 24
    PRINT_STR msg_retry

    mov ax, 0001h              ; show mouse again
    int 33h

retry_wait:
    mov ax, 0003h
    int 33h
    and bx, 1
    jz retry_wait
    jmp show_menu              

exit_game:
    mov ax, 0002h              ; hide mouse before closing dos
    int 33h
    mov ax, 0003h              
    int 10h
    mov ax, 4c00h              
    int 21h

end start