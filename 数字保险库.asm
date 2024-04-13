STACKS  SEGMENT   STACK       ;堆栈段
              DW        128 DUP(?)  ;注意这里只有128个字节
      STACKS  ENDS
DATAS SEGMENT
    IO8255_MODE_DISPLAY EQU 9006H
    IO8255_A_DISPLAY    EQU 9000H         ;控制数码管亮图型
    IO8255_B_DISPLAY    EQU 9002H         ;控制哪个数码管亮
    IO8255_C_DISPLAY    EQU 9004H

    IO8255_MODE_LOCK    EQU 8006H
    IO8255_A_LOCK       EQU 8000H
    IO8255_B_LOCK       EQU 8002H
    IO8255_C_LOCK       EQU 8004H

    IO8253_MODE_TIME    EQU 0A006H
    IO8253_A_TIME       EQU 0A000H
    IO8253_B_TIME       EQU 0A002H
    IO8253_C_TIME       EQU 0A004H

    IO8255_MODE_TIME    EQU 0B006H
    IO8255_A_TIME       EQU 0B000H
    IO8255_B_TIME       EQU 0B002H
    IO8255_C_TIME       EQU 0B004H

    IO8255_MODE_DRIVE   EQU 0C006H
    IO8255_A_DRIVE      EQU 0C000H
    IO8255_B_DRIVE      EQU 0C002H
    IO8255_C_DRIVE      EQU 0C004H

    IO8259_A            EQU 0D000H     ;8259偶地址
    IO8259_B            EQU 0D002H     ;8259奇地址
    ICW1                EQU 13H        ; 单片8259无ICW3, 上升沿中断, 要写ICW4
    ICW2                EQU 20H        ; 中断号为20H
    ICW4                EQU 03H        ; 工作在8086方式
    OCW1                EQU 0H         ; 允许中断
    NUM_SEG             DB 0C0H,0F9H,0A4H,0B0H,99H,92H,82H,0F8H,80H,90H,0C7H,0C1H  ;0-9,L,U
    INIT_MINUTES        DB 1
    INIT_SECONDS        DB 10
    SURE                EQU 23H                  ;#号
    ISLOCKED 	        DB 1                     ; 0 解锁, 1 锁定
    KEYS   		        DB 5 DUP(?)              ;存输入的密码
    KEYS_LENGTH         DB 4
    KEYS_VALUE 	        DW 0
    KEYS_TXT            DB 'Input Password:'
    KEYS_TXT_LENGTH     DB $ - KEYS_TXT
    KEYS_VALUE_STRING   DB 5 DUP(?)              ;存输入的密码字符串
    PASSWORD            DW 2333 
    FAILS		        DW 0
    ROW                 DB ?
    LINE                DB ?
    CU_ANTICLOCKWISE    DB 02H,06H,04H,0CH,08H,09H,01H,03H ;控制数据表
    CU_CLOCKWISE        DB 03H,01H,09H,08H,0CH,04H,06H,02H ;控制数据表
DATAS ENDS

CODE SEGMENT PUBLIC 'CODE'
    ASSUME CS:CODE,DS:DATAS

START: 
    MOV AX,DATAS
    MOV DS,AX
    CALL INIT_IO
    CALL SHOW_LOCK
    CALL LCD_INIT
    MAIN_LOOP:
    CALL READ_KEYS
    CALL DISPLAY_KEY
    CALL VAULT
    JMP MAIN_LOOP

INIT_IO PROC NEAR
    MOV DX,IO8255_MODE_DISPLAY
    MOV AL,88H   ;全为输出,C的高位设置成输入模式
    OUT DX,AL

    MOV DX, IO8255_MODE_LOCK
    MOV AL, 89H  ;设置显示8255控制字的工作方式,A口方式0输出，B口方式0输出，C输入
	OUT DX, AL

    MOV DX, IO8255_MODE_TIME
    MOV AL, 89H  ;设置显示8255控制字的工作方式,A口方式0输出，B口方式0输出，C输入
	OUT DX, AL

    MOV DX, IO8255_MODE_DRIVE
    MOV AL, 89H  ;设置显示8255控制字的工作方式,A口方式0输出，B口方式0输出，C输入
	OUT DX, AL

    MOV DX,IO8253_MODE_TIME
    MOV AL,16H            ;设置8253工作方式，模式3，计数器0
    OUT DX,AL
    MOV DX,IO8253_A_TIME ;计数器0初值为2
    MOV AL, 02H
    OUT DX, AL   


    CLI                     ; 关中断
    PUSH DS                 ; 保存DS
    MOV AX ,0               ; DS=0
    MOV DS ,AX              ;将数据段寄存器DS设置为0。这是为了访问内存的低地址区域，为了修改中断向量表
    MOV DI, 128             ;0X20 * 4 中断号
    MOV AX,OFFSET ADD_INT
    MOV [DI], AX            ; 将中断入口地址写入中断向量表
    MOV AX, SEG ADD_INT 
    MOV [DI+2], AX          
    POP DS                  ;恢复之前保存的DS寄存器值

    MOV DX, IO8259_A
    MOV AL, ICW1
    OUT DX, AL
    MOV DX, IO8259_B
    MOV AL, ICW2
    OUT DX, AL
    MOV AL, ICW4
    OUT DX, AL
    MOV AL, OCW1
    OUT DX, AL

    RET
INIT_IO ENDP

SHOW_LOCK PROC NEAR
    XOR AX, AX
    CMP ISLOCKED, 1
    JE LOCKING
    JMP UNLOCKING
;锁的情况下的显示
LOCKING:
    MOV DX, IO8255_A_LOCK
	MOV AL, NUM_SEG[0AH]            ;数码管显示L
	OUT DX, AL                      ;输出到数码管,OUT这里要写寄存器不然会报错error A2070: invalid instruction operands
    JMP SHOW_LOCK_FIN
;解锁的情况下的显示
UNLOCKING:
    MOV DX, IO8255_A_LOCK
    MOV AL, NUM_SEG[0BH]            ;数码管显示U
    OUT DX, AL                      ;输出到数码管
    XOR AX, AX                      ;FAILS清零
	MOV FAILS, AX	
    JMP SHOW_LOCK_FIN

SHOW_LOCK_FIN:
    RET
SHOW_LOCK ENDP


;读入5个数
READ_KEYS PROC NEAR   
    MOV SI, 0
READ_START:
    CALL SHOW_LOCK            ;显示
	CMP ISLOCKED, 1      ;锁定状态跳转
	JE READ_FIVE_KEYS    ;读取输入的密码
	CMP SI, 4            ;非锁定重设密码，输入4位密码
	JE READ_FINSH

READ_FIVE_KEYS:	
    CMP SI, 5            ;已经输入5个数，跳转结束
    JE READ_FINSH

    ;第一列
    MOV DX, IO8255_B_LOCK
    MOV AX, 00000100b
    OUT DX, AX
    MOV DX, IO8255_C_LOCK
    IN AL, DX	
    AND AL, 0FH
    JNZ CHECK_FIRST_COL

    ;第二列
    MOV DX, IO8255_B_LOCK
    MOV AX, 00000010b
    OUT DX, AX
    MOV DX, IO8255_C_LOCK
    IN AL, DX
    AND AL, 0FH
    JNZ CHECK_SECOND_COL

    ;第三列
    MOV DX, IO8255_B_LOCK
    MOV AX, 00000001b
    OUT DX, AX
    MOV DX, IO8255_C_LOCK
    IN AL, DX
    AND AL, 0FH
    JNZ CHECK_THIRD_COL

    JMP READ_START

CHECK_FIRST_COL:
    CALL WAIT_KEY

    check_one:
    TEST AL, 00000001b     ;判断是否按下1
    JZ check_four
    MOV BL, 1
    MOV KEYS[SI], BL       ;将按下的键值存入数组
    ADD BL, '0' 
    MOV KEYS_VALUE_STRING[SI], BL;将按下的键值存入字符串
    INC SI
    JMP READ_START

    check_four:
    TEST AL, 00000010b     ;判断是否按下4  
    JZ check_seven
    MOV BL, 4
    MOV KEYS[SI], BL
    ADD BL, '0' 
    MOV KEYS_VALUE_STRING[SI], BL;将按下的键值存入字符串
    INC SI
    JMP READ_START

    check_seven:
    TEST AL, 00000100b     ;判断是否按下7
    JZ check_star
    MOV BL, 7
    MOV KEYS[SI], BL
    ADD BL, '0' 
    MOV KEYS_VALUE_STRING[SI], BL;将按下的键值存入字符串
    INC SI
    JMP READ_START

    check_star:
    TEST AL, 00001000b     ;判断是否按下*,按下*清空重新输入
    JNZ READ_RESTART
    JMP READ_START
						
CHECK_SECOND_COL:
    CALL WAIT_KEY

    check_two:
    TEST AL, 00000001b     ;判断是否按下2
    JZ check_five
    MOV BL, 2
    MOV KEYS[SI], BL
    ADD BL, '0' 
    MOV KEYS_VALUE_STRING[SI], BL;将按下的键值存入字符串
    INC SI
    JMP READ_START

    check_five:
    TEST AL, 00000010b     ;判断是否按下5
    JZ check_eight
    MOV BL, 5
    MOV KEYS[SI], BL    
    ADD BL, '0' 
    MOV KEYS_VALUE_STRING[SI], BL;将按下的键值存入字符串
    INC SI
    JMP READ_START

    check_eight:
    TEST AL, 00000100b    ;判断是否按下8
    JZ check_zero
    MOV BL, 8
    MOV KEYS[SI], BL
    ADD BL, '0' 
    MOV KEYS_VALUE_STRING[SI], BL;将按下的键值存入字符串
    INC SI
    JMP READ_START

    check_zero:   
    TEST AL, 00001000b     ;判断是否按下0
    JZ READ_START
    MOV BL, 0
    MOV KEYS[SI], BL
    ADD BL, '0' 
    MOV KEYS_VALUE_STRING[SI], BL;将按下的键值存入字符串
    INC SI
    JMP READ_START
			
CHECK_THIRD_COL:
    CALL WAIT_KEY

    check_three:
    TEST AL, 00000001b     ;判断是否按下3
    JZ check_six
    MOV BL, 3
    MOV KEYS[SI], BL
    ADD BL, '0' 
    MOV KEYS_VALUE_STRING[SI], BL;将按下的键值存入字符串
    INC SI
    JMP READ_START

    check_six:
    TEST AL, 00000010b     ;判断是否按下6
    JZ check_nine
    MOV BL, 6
    MOV KEYS[SI], BL
    ADD BL, '0' 
    MOV KEYS_VALUE_STRING[SI], BL;将按下的键值存入字符串
    INC SI
    JMP READ_START

    check_nine:
    TEST AL, 00000100b     ;判断是否按下9
    JZ check_sure
    MOV BL, 9
    MOV KEYS[SI], BL
    ADD BL, '0' 
    MOV KEYS_VALUE_STRING[SI], BL;将按下的键值存入字符串
    INC SI
    JMP READ_START

    check_sure:
    TEST AL, 00001000b     ;判断是否按下#
    JZ READ_START
    MOV BL, SURE
    MOV KEYS[SI], BL
    MOV KEYS_VALUE_STRING[SI], BL
    INC SI
    JMP READ_START
				
				
READ_RESTART:	
    MOV SI,0
	JMP READ_START
						
READ_FINSH:		
    RET
READ_KEYS ENDP

;等待按键松开
WAIT_KEY  PROC NEAR
    PUSH AX		     ;保存AX
    PUSH DX		     ;保存DX
WAIT_LOOP:
    MOV DX, IO8255_C_LOCK		 
    IN AL, DX
	CMP AL, 0H       ;判断是否松开按键
	JNE WAIT_LOOP	
    POP DX	 
	POP AX

    RET
WAIT_KEY  ENDP

;存的密码是千位数字，将key数字的元素变为千位数字
DECODE PROC NEAR ;密码比对
	MOV BX, 10
	MOV CX, 3
	XOR AX, AX
	XOR SI, SI
				
DECODE_LOOP:	
	ADD AL, KEYS[SI]
	MUL BX
	INC SI
	LOOP DECODE_LOOP
	ADD AL, KEYS[SI]
	MOV KEYS_VALUE, AX	

	RET
DECODE ENDP

VAULT PROC NEAR 
    CMP ISLOCKED, 1			;判断是否为锁定状态

    JNE	UNLOCKED

    MOV AL, KEYS[4]         ;检查第5个元素
    CMP AL,SURE             ;是否为#号
    JNE VAULT_FINSH

    CALL DECODE             ;成功输入密码
    MOV AX, KEYS_VALUE
    CMP AX, PASSWORD    ;比较密码是否相等
    JZ OPEN_VAULT           ;相等成功开锁
    JMP FAIL                 ;不相等失败
				
OPEN_VAULT:
    CALL DRIVE_RUN               ;开锁		
    MOV ISLOCKED, 0              ;解锁
    CALL SHOW_LOCK
	JMP VAULT_FINSH

UNLOCKED:		
    CALL DECODE
    MOV AX, KEYS_VALUE
    MOV PASSWORD, AX
    CALL DRIVE_RUN               ;上锁
    MOV ISLOCKED, 1              ;锁定
    CALL SHOW_LOCK
    JMP VAULT_FINSH
				
FAIL:			
    MOV AX, FAILS
    INC AX
    MOV FAILS, AX
    CMP AX, 3
    JNE VAULT_FINSH
    CALL FAIL_LOCK               ;失败锁定

VAULT_FINSH:
    RET
VAULT ENDP

DISPLAY_KEY PROC NEAR
    ;显示提示信息
   	MOV ROW,00H;设置行
   	MOV LINE,00H;设置列
    LEA DI,KEYS_TXT
    MOV CL,KEYS_TXT_LENGTH
   	CALL SHOW_STRING
    ;显示输入的密码
    MOV ROW,01H;设置行
   	MOV LINE,00H;设置列
   	LEA DI,KEYS_VALUE_STRING
    MOV CL,KEYS_LENGTH
   	CALL SHOW_STRING

DISPLAY_KEY ENDP

SET_CURSOR PROC NEAR
	PUSH BX
	MOV BL,LINE
	MOV BH,ROW
	CMP BH,00H
	JA ROW_2;大于说明再第二行
ROW_1:
	ADD BL,00H
	OR BL,80H
	MOV AL,BL
	JMP SET_CURSOR_FIN	
ROW_2:
	ADD BL,40H
	OR BL,80H
	MOV AL,BL
SET_CURSOR_FIN:
	POP BX
	RET
SET_CURSOR ENDP

SHOW_STRING PROC NEAR   ;数据在DI中，长度在CL中
	MOV CH,00H
	CALL SET_CURSOR     ;得到的al的结果即为要显示的数据的位置
   	CALL LCD_WCMD
SHOW_STRING_LOOP:
	MOV AL,[DI]
	CALL LCD_WDATA
	INC DI
	LOOP SHOW_STRING_LOOP
	RET
SHOW_STRING ENDP

LCD_INIT PROC NEAR      ;初始化函数
    MOV AL,30H
    CALL LCD_WCMD
	MOV AL,38H          ;16*2显示，5*7点阵，8位数据接口
	CALL LCD_WCMD
	MOV AL,0CH          ;显示器开，光标关闭
	CALL LCD_WCMD
    MOV AL,01H          ;清屏
	CALL LCD_WCMD
	MOV AL,06H          ;文字不动，地址自动+1
	CALL LCD_WCMD
	RET
LCD_INIT ENDP

LCD_WCMD PROC NEAR        ;写命令函数,把命令存储在AL中
	CALL WAIT_READY_LCD	  ;确保LCD准备好接收新命令
	MOV BL,00H            ;RS和RW都为低电平表示命令模式，输出
	CALL RW_RS_SET
	MOV BL,01H            ;先需要设置E为低电平
	CALL E_SET
	MOV DX,IO8255_A_DISPLAY
	OUT DX,AL
	MOV BL,00H            ;再设E为高电平
	CALL E_SET
	RET
LCD_WCMD ENDP

LCD_WDATA PROC NEAR           ;写数据函数,把数据存储在al中
	CALL WAIT_READY_LCD
	MOV BL,01H                ;RS=1,RW=0表示数据模式，输出
	CALL RW_RS_SET
	MOV BL,01H                ;先需要设置E为低电平
	CALL E_SET
	MOV DX,IO8255_A_DISPLAY
	OUT DX,AL
	MOV BL,00H                ;再设E为高电平
	CALL E_SET
	RET
LCD_WDATA ENDP

WAIT_READY_LCD PROC NEAR;等待LCD准备好
	PUSH AX
	MOV DX,IO8255_A_DISPLAY;先输出A口为0ffh
	MOV AL,0FFH
	OUT DX,AL
	MOV BL,02H;      ; 02h 表示 RW=1, RS=0（命令模式，读操作）
	CALL RW_RS_SET
WAIT_READY_LCD_Loop:
	MOV BL,01H
	CALL E_SET     
	MOV DX,IO8255_C_DISPLAY;从C口读入命令字
	IN AL,DX
	TEST AL,80H;与运算判断输入的第八位是否为1
	MOV BL,00H
	CALL E_SET
	JNZ WAIT_READY_LCD_Loop;高位为1表示还没有处理完
	POP AX
	RET
WAIT_READY_LCD ENDP

RW_RS_SET PROC NEAR
;对应PB0,PB1，先把数据存在BL中
; 00h 表示 RW=0, RS=0（命令模式，写操作）
; 01h 表示 RW=0, RS=1（数据模式，写操作）
; 02h 表示 RW=1, RS=0（命令模式，读操作）
	PUSH AX
	MOV DX,IO8255_B_DISPLAY
	MOV AL,BL
	OUT DX,AL
	POP AX
	RET
RW_RS_SET ENDP

E_SET PROC NEAR
;对应PC4，先把数据存在BL中
;控制液晶显示屏（LCD）的使能（E）信号
	PUSH AX
	MOV DX,IO8255_C_DISPLAY
	MOV AL,BL
	OUT DX,AL
	POP AX
	RET
E_SET ENDP

DELAY PROC NEAR
    PUSH CX
    MOV CX,0D1H
    DELAY_LOOP: 
    NOP
    NOP
    NOP
    NOP
    LOOP DELAY_LOOP
    POP CX
    RET
DELAY ENDP

DRIVE_RUN PROC NEAR
    PUSH AX                  ;保存寄存器
    PUSH BX
    PUSH CX
    PUSH DX
    PUSH DI
    MOV AL,0FFH
    MOV BL,0H                ;选择计数器
    MOV DL,ISLOCKED
    CMP DL,1                 ;判断是否为锁定状态
    JE OPEN_LOCK             ;锁定状态跳转
    JMP CLOSE_LOCK

OPEN_LOCK:
    MOV CX,08H               ;循环8次
    LEA DI,CU_ANTICLOCKWISE  ;将CU_ANTICLOCKWISE的地址传给DI
    LOOP_CU_ANTICLOCKWISE: 
    MOV AL,[DI]              ;将DI指向的值传给AL
    MOV DX,IO8255_B_DRIVE    ;将IO8255_B_DRIVE的地址传给DX
    OUT DX,AL                ;将AL的值传给DX
    INC DI                   ;DI指向下一个
    INC BL                   ;BL加1
    CALL DELAY
    LOOP LOOP_CU_ANTICLOCKWISE
    CMP BL,0F0H              ;判断是否转够了圈
    JE DRIVE_RUN_FIN
    JMP OPEN_LOCK

CLOSE_LOCK:
    MOV CX,08H
    LEA DI,CU_CLOCKWISE
    LOOP_CU_CLOCKWISE: 
    MOV AL,[DI]
    MOV DX,IO8255_B_DRIVE
    OUT DX,AL
    INC DI
    INC BL
    CALL DELAY
    LOOP LOOP_CU_CLOCKWISE
    CMP BL,0F0H
    JE DRIVE_RUN_FIN
    JMP CLOSE_LOCK

DRIVE_RUN_FIN:
    POP DI
    POP DX
    POP CX
    POP BX
    POP AX
    RET
DRIVE_RUN ENDP

ADD_INT PROC NEAR
    CLI                     ; 关中断
    INC BX
    CALL DISPLAY_7SEG
    STI                     ; 开中断
    IRET
ADD_INT ENDP

FAIL_LOCK PROC NEAR
    STI
    MOV BX, 0
    CALL DISPLAY_7SEG
    DISPLAY_TIME:
    CMP BX, 0BH
    JNE DISPLAY_TIME
    CLI
    RET
FAIL_LOCK ENDP

DISPLAY_7SEG PROC NEAR 
    MOV DX, IO8255_A_TIME
    MOV SI, BX
    MOV AL, NUM_SEG[SI]
    OUT DX, AL
    CALL DELAY
    RET
DISPLAY_7SEG ENDP

CODE ENDS
    END START

