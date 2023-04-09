let canvas = document.getElementById('canvas');
let ctx = canvas.getContext('2d');
let SCALE = 4.;
canvas.width = 320*SCALE;
canvas.height = 200*SCALE;

let vga = [];
for (let i = 0; i < 320*200; i++) {
    vga.push(0);
}

let paletteData = [];
for (let i = 0; i < 256*3; i++) {
    paletteData.push(0);
}

let curcol = -1;
function plot(x, y, col) {
    if (col != curcol) {
        let r = paletteData[col * 3] * 4;
        let g = paletteData[col * 3 + 1] * 4;
        let b = paletteData[col * 3 + 2] * 4;
        ctx.fillStyle = `rgb(${r}, ${g}, ${b})`;
        curcol = col;
    }
    ctx.fillRect(x * SCALE, y * SCALE, SCALE, SCALE);
}

paletteData[3 * 0x28] = 63;
paletteData[3 * 0x28 + 1] = 0;
paletteData[3 * 0x28 + 2] = 0;

paletteData[3 * 0x1e] = 59;
paletteData[3 * 0x1e + 1] = 59;
paletteData[3 * 0x1e + 2] = 59;

paletteData[3 * 0x1f] = 63;
paletteData[3 * 0x1f + 1] = 63;
paletteData[3 * 0x1f + 2] = 63;

function blit() {
    for (let y = 0; y < 200; y++) {
        for (let x = 0; x < 320; x++) {
            plot(x, y, vga[320 * y + x]);
        }
    }
}

let draws = [
    // pipe red
    [
        47,
        -32,
        (4 << 8) + 0x28,
        256+32,
    ],
    // pipe white extension
    [
        11*320+46,
        -128,
        (16 << 8) + 0x1e,
        400,
    ],
    // white body upper/right
    [
        14*320+30,
        -128,
        (97 << 8) + 0x1f,
        256+128,
    ],
    // white body lower/left
    [
        23*320+9,
        -90,
        (30 << 8) + 0x1f,
        0,
    ],
    // red bottom
    [
        29*320,
        120,
        (160 << 8) + 0x28,
        -255,
    ]
];

let di = 0;
let bp, bx, dx;
bx = 0x20cd;
for (let d of draws) {
    console.log(';');
    //lodsw        ; delta di
    //add di, ax
    let targetDi = d[0];
    let initialStartPos = bx >> 8;
    let correction = targetDi - initialStartPos - di;
    console.log("dw", correction);

    di += correction;

    //lodsb        ; delta startPos
    //movsx bp, al
    bp = d[1];
    console.log("db", d[1]);
    //lodsw        ; initial width + color
    //mov dx, ax
    dx = d[2];
    console.log("dw", d[2]);
    console.log("dw", d[3]);

    //mov cl, 16 ; number of rows
    //primitive_loop:
    for (let i = 0; i < 16; i++) {
        //pusha ; save di, cx
        //movsx bp, bh ; startPos integer part
        let bp2 = bx >> 8;
        //add di, bp ; di += int(startPos)
        let di2 = di + bp2;
        //xchg cl, dh ; cx = int(width)
        let cx2 = dx >> 8;
        //rep stosb
        //popa ; restore di, cx

        let row = (di2/320)|0;
        let col = di2%320;

        do {
            vga[di2++] = d[2] & 0xff;
        } while (--cx2);
        //add di, 320
        di += 320;
        //add dx, [si]   ; increment width (fixed point)
        dx += d[3];
        //add bx, bp     ; increment startPos (fixed point)
        bx += bp;
        //loop primitive_loop
        //lodsw ; si += 2
    }
}
blit();
