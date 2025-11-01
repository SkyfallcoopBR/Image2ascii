.intel_syntax noprefix
.global main

.section .note.GNU-stack,"",@progbits

.extern fopen, fclose, fscanf, fprintf, malloc, free, exit, printf

.section .data
    mode_r:
        .string "r"
    mode_w:
        .string "w"
    fmt_int:
        .string "%d"
    fmt_hex:        
        .string "%x"
    fmt_char:       
        .string "%c"
    fmt_newline:    
        .string "\n"
    fmt_header:     
        .string "[%d]\n"
    error_msg:
        .string "Uso: %s <arquivo_entrada> <arquivo_saida>\n"

.section .bss
    .lcomm in_fp, 8
    .lcomm out_fp, 8
    .lcomm palette, 64      # 16 * 4 bytes
    .lcomm pixel_buffer, 8
    .lcomm width, 4         # Variável para largura
    .lcomm height, 4        # Variável para altura  
    .lcomm num_images, 4    # Variável para número de imagens
    .lcomm num_bytes, 4
    .lcomm hex_values_ptr, 8    # Ponteiro para buffer alocado dinamicamente
    .lcomm max_hex_values, 4    # Tamanho máximo alocado

.section .text

main:
    push rbp 
    mov rbp, rsp
    
    # Garante que r15 é o ponteiro para argv
    mov r15, rsi
    
    # Verifica se temos os argumentos necessários (argc deve ser 3)
    cmp rdi, 3
    jne usage_error
    
    # Abre arquivo de entrada (argv[1])
    mov rdi, [r15 + 8]
    lea rsi, [rip + mode_r]
    call fopen
    test rax, rax
    jz file_error
    mov [rip + in_fp], rax
    
    # Abre arquivo de saída (argv[2])
    mov rdi, [r15 + 16]
    lea rsi, [rip + mode_w]
    call fopen
    test rax, rax
    jz file_error
    mov [rip + out_fp], rax

    xor rbx, rbx
    
    # Lê paleta (16 valores)
    xor r12, r12
read_palette:
    cmp r12, 16
    jge palette_done
    
    lea rdx, [rip + palette]
    mov rax, r12
    shl rax, 2
    add rdx, rax
    
    mov rdi, [rip + in_fp]
    lea rsi, [rip + fmt_int]
    call fscanf
    
    # Verificar se fscanf funcionou
    cmp eax, 1
    jne read_palette_error
    
    inc r12
    jmp read_palette

palette_done:
    # Lê número de imagens
    mov rdi, [rip + in_fp]
    lea rsi, [rip + fmt_int]
    lea rdx, [rip + num_images]
    call fscanf
    
    xor rbx, rbx

image_loop:
    cmp ebx, [rip + num_images]
    jge all_done
    
    # Lê número de bytes desta imagem
    mov rdi, [rip + in_fp]
    lea rsi, [rip + fmt_int]
    lea rdx, [rip + num_bytes]
    call fscanf
    
    mov r13d, [rip + num_bytes]
    xor r14, r14

hex_allocation:
    mov eax, [rip + num_bytes]
    cmp eax, 0
    jle allocation_error
    
    # Aloca dinamicamente
    mov rdi, rax
    shl rdi, 2
    call malloc
    test rax, rax
    jz malloc_error
    
    mov [rip + hex_values_ptr], rax
    mov eax, [rip + num_bytes]
    mov [rip + max_hex_values], eax

read_hex_loop:
    cmp r14d, r13d
    jge hex_done
    
    # PROTEÇÃO ADICIONAL
    cmp r14d, [rip + max_hex_values]
    jge buffer_overflow_error
    
    mov rdi, [rip + in_fp]
    lea rsi, [rip + fmt_hex]
    mov rdx, [rip + hex_values_ptr]
    mov rax, r14
    shl rax, 2
    add rdx, rax
    call fscanf
    
    # Verificar se fscanf funcionou
    cmp eax, 1
    jne read_hex_error
    
    inc r14
    jmp read_hex_loop

hex_done:
    # Lê altura e largura desta imagem
    mov rdi, [rip + in_fp]
    lea rsi, [rip + fmt_int]
    lea rdx, [rip + height]
    call fscanf
    
    mov rdi, [rip + in_fp]
    lea rsi, [rip + fmt_int]  
    lea rdx, [rip + width]
    call fscanf
    
    # Calcula o número total de pixels e aloca dinamicamente
    mov eax, [rip + height]
    imul eax, [rip + width]
    mov rdi, rax
    call malloc
    test rax, rax
    jz malloc_error
    mov [rip + pixel_buffer], rax
    
    # Imprime header da imagem
    mov rdi, [rip + out_fp]
    lea rsi, [rip + fmt_header]
    mov rdx, rbx
    call fprintf
    
    # Decodifica imagem atual
    mov r14, [rip + pixel_buffer]
    xor r15d, r15d
    xor r12d, r12d
    mov eax, [rip + height]
    imul eax, [rip + width]
    mov r13d, eax

decode_current_image:
    cmp r15d, r13d
    jge print_current_image
    
    # CORREÇÃO CRÍTICA: usar hex_values_ptr ao invés de hex_values
    mov r10, [rip + hex_values_ptr]  # ✅ CORRIGIDO!
    mov r11d, r12d
    shl r11d, 2
    movsx r11, r11d
    mov edi, [r10 + r11]
    
    # Extrai repetições e índice
    mov r8d, edi
    shr r8d, 4
    and edi, 0x0F
    
    # Prepara para preencher
    mov ecx, r8d
    lea rdx, [rip + palette]
    mov r10d, edi
    shl r10d, 2
    movsx r10, r10d
    mov r9d, [rdx + r10]
    
    inc r12d

fill_current_pixels:
    cmp r15d, r13d
    jge print_current_image
    
    test ecx, ecx
    jz decode_current_image
    
    mov [r14], r9b
    inc r14
    inc r15d
    dec ecx
    jmp fill_current_pixels

print_current_image:
    xor r12d, r12d
    
line_loop:
    cmp r12d, [rip + height]
    jge next_image
    
    xor r13d, r13d
    
column_loop:
    cmp r13d, [rip + width]
    jge end_line
    
    # Calcula posição no buffer
    mov eax, r12d
    imul eax, [rip + width]
    add eax, r13d
    
    # Pega pixel do buffer
    mov r14, [rip + pixel_buffer]
    movzx eax, byte ptr [r14 + rax]
    
    # Imprime caractere
    mov rdi, [rip + out_fp]
    lea rsi, [rip + fmt_char]
    mov rdx, rax
    call fprintf
    
    inc r13d
    jmp column_loop

end_line:
    mov rdi, [rip + out_fp]
    lea rsi, [rip + fmt_newline]
    call fprintf
    
    inc r12d
    jmp line_loop

next_image:
    # Libera hex_values_ptr
    mov rdi, [rip + hex_values_ptr]
    test rdi, rdi
    jz skip_hex_free
    call free
    mov qword ptr [rip + hex_values_ptr], 0

skip_hex_free:
    # Libera pixel_buffer
    mov rdi, [rip + pixel_buffer]
    test rdi, rdi
    jz skip_pixel_free
    call free
    mov qword ptr [rip + pixel_buffer], 0

skip_pixel_free:
    inc rbx
    jmp image_loop

all_done:
    mov rdi, [rip + in_fp]
    call fclose
    
    mov rdi, [rip + out_fp]
    call fclose
    
    xor eax, eax
    pop rbp
    ret

# LABELS DE ERRO ADICIONADOS:
read_palette_error:
    mov rdi, [rip + in_fp]
    call fclose
    mov rdi, [rip + out_fp]
    call fclose
    mov eax, 1
    pop rbp
    ret

allocation_error:
    mov rdi, [rip + in_fp]
    call fclose
    mov rdi, [rip + out_fp]
    call fclose
    mov eax, 1
    pop rbp
    ret

buffer_overflow_error:
    mov rdi, [rip + hex_values_ptr]
    test rdi, rdi
    jz skip_hex_free_overflow
    call free
skip_hex_free_overflow:
    mov rdi, [rip + in_fp]
    call fclose
    mov rdi, [rip + out_fp]
    call fclose
    mov eax, 1
    pop rbp
    ret

read_hex_error:
    mov rdi, [rip + hex_values_ptr]
    test rdi, rdi
    jz skip_hex_free_read
    call free
skip_hex_free_read:
    mov rdi, [rip + in_fp]
    call fclose
    mov rdi, [rip + out_fp]
    call fclose
    mov eax, 1
    pop rbp
    ret

usage_error:
    mov rdi, 1
    lea rsi, [rip + error_msg]
    mov rdx, [r15]
    call printf
    mov eax, 1
    pop rbp
    ret

file_error:
    mov eax, 1
    pop rbp
    ret

malloc_error:
    mov rdi, [rip + in_fp]
    call fclose
    mov rdi, [rip + out_fp]
    call fclose
    mov eax, 1
    pop rbp
    ret
