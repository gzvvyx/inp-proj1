# INP Project 1

Processor able to execute version of the Brainfuck language

## Instructions

| Command | Op. code |       Description       |   C equivalent   |
|:-------:|:--------:|:------------------------|:-----------------|
|    >    |   0x3E   | increment pointer value | ptr += 1         |
|    <    |   0x3C   | decrement pointer value | ptr -= 1         |
|    +    |   0x2B   | increment cell value    | *ptr += 1        |
|    -    |   0x2D   | decrement cell value    | *ptr -= 1        |
|    [    |   0x5B   | begin while cycle       | while (*ptr) {   |
|    ]    |   0x5D   | end while cycle         | .. }             |
|    (    |   0x28   | begin do while cycle    | do {             |
|    )    |   0x29   | end do while cycle      | } while (*ptr)   |
|    .    |   0x2E   | print cell value        | putchar(*ptr)    |
|    ,    |   0x2X   | load value to cell      | *ptr = getchar() |
|   null  |   0x00   | end program             | return           |

## Evaluation

**login.b**: 3b počet instrukcí: 89, tj. o 34 více než nejkompaktnější odevzdané řešení <br>
**login.png**: 3b <br>
**cpu.vhd**: 16b jednoduché smyčky: ok vnořené smyčky: ok

### 22/23