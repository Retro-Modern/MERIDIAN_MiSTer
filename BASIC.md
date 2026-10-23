# MERIDIAN BASIC – command reference

This is the reference for the commands that MERIDIAN adds to Microsoft BASIC:
syntax, value ranges, and a short example for each. Every example was typed
into a MERIDIAN on a MiSTer and runs as shown. The README has the overview;
`KONZEPT.md` (German) has the chips and the memory map in full detail; the
programs in `programme/` (and on the demo disk) are longer examples.

**Contents**

- [Basics](#basics) – typing, what is different from other Microsoft BASICs
- [Screen and text](#screen-and-text) – `CLS` `COLOR` `MODE`
- [Graphics](#graphics) – `GRAPHIC` `PLOT` `LINE` `PALETTE` `GRADIENT` `STAMP` `BLIT`
- [The PINSEL look](#the-pinsel-look) – `SHINE` `GLOW` `INK` `LOOK`
- [Sprites](#sprites) – `PATTERN` `SPRITE` `HIT()`
- [Workshop data](#workshop-data) – `MAP` `TILE` `TILE()` `SFX` `LOOK`
- [Sound and music](#sound-and-music) – `SOUND` `SILENCE` `SAMPLE` `PLAY` `SONG` `SONG()`
- [Input](#input) – `KEY()` `JOY()` `MOUSE` `MOUSE()` `GET`
- [Time](#time) – `PAUSE` `CLOCK()`
- [Program flow](#program-flow) – `IF … ELSE` `WHILE … WEND` `REPEAT … UNTIL` `RENUMBER`
- [Drives and files](#drives-and-files) – `DRIVE` `DIR` `SAVE` `LOAD` `BSAVE` `BLOAD` `SCRATCH` `HEADER`
- [Network](#network) – `NET` `NET()` `NET$()`
- [Memory and machine code](#memory-and-machine-code) – `PEEK` `POKE` `WAIT` `FRE` `USR` `MONITOR`
- [Error messages](#error-messages)
- [All MERIDIAN words at a glance](#all-meridian-words-at-a-glance)

## Basics

The BASIC is Microsoft BASIC M6502 1.1 from 1978. Everything from
Microsoft works as usual: `PRINT` (or `?`), `INPUT`, `GET`, `IF … THEN`,
`FOR … NEXT`, `GOTO`, `GOSUB`, `ON … GOTO`, `DIM`, `DATA`/`READ`/`RESTORE`,
`DEF FN`, the string functions, `RND`, `LIST`, `RUN`, `NEW`, `CONT` and so
on. Numbers have 9 digits, 47 102 bytes are free for programs.

- `Esc` stops a running program, `Shift+Home` clears the screen.
- `F1`–`F6` open the workshop while BASIC waits for a command (see the
  README).
- `GET` does not wait: it returns `""` when no key is waiting.
- `PEEK`, `POKE` and `WAIT` take 24-bit addresses (0–16 777 215), see
  [Memory](#memory-and-machine-code). `FRE(0)` never goes negative.
- Small letters outside quotes become capitals when you press Return, so
  `print` works like `PRINT`; text in quotes and answers to `INPUT` stay as
  typed.

**Pitfalls inherited from 1978:**

- Only the first **two letters** of a variable name count: `SCORE` and
  `SC` are the same variable.
- Keywords are found **inside names**: `SCORE` is read as `SC OR E`, `KEYS`
  as `KEY S`, `DIRT` as `DIR T`. Keep names short (`S`, `X1`, `P$`).
  `tools/bas.py` warns about this when you write programs on a computer.

## Screen and text

The text screen has 30 rows of 40 or 80 characters. At power-on the text
is light blue (14) on blue (6).

### CLS

Clears the text screen with the current background colour.

### COLOR fg[,bg]

Text colour `fg` and background `bg` (0–15) for everything printed after
it. `CLS` fills the whole screen with `bg`.

```basic
10 COLOR 1,0:CLS
20 FOR C=0 TO 15:COLOR C,0:PRINT "COLOUR";C:NEXT
30 COLOR 14,6:PRINT "BACK TO LIGHT BLUE ON BLUE"
```

The 16 text colours (they are colours 0–15 of the palette, see `PALETTE`):

| | | | | | | | |
|---|---|---|---|---|---|---|---|
| 0 black | 1 white | 2 red | 3 turquoise | 4 violet | 5 green | 6 blue | 7 yellow |
| 8 orange | 9 brown | 10 light red | 11 dark grey | 12 grey | 13 light green | 14 light blue | 15 light grey |

### MODE 40 / MODE 80

40 or 80 characters per row; clears the screen.

```basic
MODE 80:PRINT "EIGHTY COLUMNS"
```

## Graphics

`GRAPHIC 1` puts a bitmap of 320×240 pixels with 256 colours in front of
the text. Colour 0 is transparent, so the text shows through where nothing
is drawn. Coordinates: x 0–319 from the left, y 0–239 from the top.

Colours 16–255 are 30 colour families of 8 shades each, darkest first:
16 red, 24 crimson, 32 orange, 40 gold, 48 ochre, 56 wood, 64 skin,
72 peach, 80 olive, 88 grass, 96 forest, 104 emerald, 112 turquoise,
120 petrol, 128 sky, 136 blue, 144 indigo, 152 violet, 160 purple,
168 magenta, 176 grey, 184 stone, 192 warm grey, 200 sand, 208 brick,
216 lavender, 224 mint, 232 neon pink, 240 neon cyan, 248 neon green.
So `40` is the darkest gold and `47` the brightest.

### GRAPHIC 1 / GRAPHIC 0

`GRAPHIC 1` switches the bitmap on and clears it (also when it is already
on – handy for "clear the picture"). `GRAPHIC 0` switches it off.

### PLOT x,y[,c]

Sets a pixel in colour `c` (0–255). Without `c` the last colour is used
(1 after `GRAPHIC 1`).

### LINE x1,y1,x2,y2[,c]

Draws a line, colour as with `PLOT`.

```basic
10 GRAPHIC 1
20 FOR I=0 TO 31:C=16+I*7
30 LINE 160,120,I*10,0,C:LINE 160,120,I*10,239,C
40 NEXT
50 FOR I=1 TO 500:PLOT RND(1)*320,RND(1)*240,1:NEXT
60 GET K$:IF K$="" THEN 60
70 GRAPHIC 0
```

### PALETTE n,r,g,b

Mixes colour `n` (0–255) anew from red, green and blue (0–15 each). It
changes the colour everywhere at once – text, graphics, sprites – also
what is already on the screen.

### GRADIENT y1,r1,g1,b1,y2,r2,g2,b2

A colour gradient for the screen background from row `y1` to row `y2`
(0–239), from colour r1,g1,b1 to r2,g2,b2 (0–15 each). The copper chip
changes the background colour on every row, so it costs BASIC no time.
Several gradients add up; `GRADIENT` alone switches them off and gives the
background its start colour back. It works on the background colour that
is set when the first gradient starts (`COLOR …,bg`).

```basic
10 CLS:PRINT "SUNSET"
20 GRADIENT 0,0,0,4,119,15,6,2:GRADIENT 120,15,6,2,239,2,0,4
30 PAUSE 180:GRADIENT
40 FOR I=15 TO 0 STEP -1:PALETTE 14,I,I,15:PAUSE 4:NEXT
50 PALETTE 14,8,11,15
```

Line 40 fades the text colour 14 from white to blue, line 50 sets it back.

### STAMP adr,x,y,w,h

Copies a picture of `w`×`h` pixels (one byte per pixel, row by row) from
address `adr` into the bitmap at x,y. Colour 0 in the picture is
transparent. The picture can lie in expansion memory (from 262 144, see
[Memory](#memory-and-machine-code)). `tools/bild2mer.py` turns a PNG into
such a picture for `BLOAD`.

### BLIT from,to,length

Copies `length` bytes with the blitter chip – fast, from and to any 24-bit
address, overlapping is fine. The bitmap starts at **131 072** with 320
bytes per row (76 800 bytes in all).

```basic
10 GRAPHIC 1:A=262144
20 FOR Y=0 TO 15:FOR X=0 TO 15:C=0
30 IF ABS(X-7.5)+ABS(Y-7.5)<8 THEN C=40+((X+Y) AND 7)
40 POKE A+Y*16+X,C:NEXT:NEXT
50 FOR I=1 TO 40:STAMP A,RND(1)*304,RND(1)*104,16,16:NEXT
60 BLIT 131072,131072+320*120,320*120
70 GET K$:IF K$="" THEN 70
80 GRAPHIC 0
```

Lines 20–40 draw a 16×16 diamond into expansion memory (0 = transparent
corners), line 50 stamps it 40 times into the upper half, line 60 copies
the upper half of the bitmap into the lower half.

## The PINSEL look

Three effects of the video chip that give MERIDIAN pictures their own look.
All three stay on after the program ends, until they are switched off.
`programme/abend.bas` (`ABEND.BAS` on the demo disk) uses all of them.

### SHINE c,y,r,g,b

A shine point: colour `c` (0–255) has the colour r,g,b (0–15 each) in row
`y` (0–239). Between two points of the same colour you get a smooth
gradient without steps, above the first and below the last point the
colour of that point. `SHINE c` removes the points of colour `c`, `SHINE`
alone removes all. At most 16 shine channels (one per point, plus one
when a colour's first point is not in row 0).

SHINE writes the colour into the palette row by row; when it is switched
off, the colour keeps the value of the last row. `LOOK 0` (or `PALETTE`)
sets the start colours again.

### GLOW s[,c,c…]

Colours `c` glow with strength `s` (1–15): a soft halo around every pixel
in that colour, also around text. Up to 7 colours per command, more with
the next `GLOW`. `GLOW` or `GLOW 0` switches all glowing off.

```basic
10 CLS:SHINE 6,0,0,0,2:SHINE 6,239,4,8,15
20 GLOW 12,7:COLOR 7:PRINT "THIS LINE GLOWS"
30 COLOR 14:PRINT "THIS ONE DOES NOT"
```

Line 10 turns the background colour 6 into a gradient from night blue to
light blue. Afterwards `SHINE:GLOW:LOOK 0` brings everything back.

### INK c[,dx,dy[,b]]

Ink in colour `c`: an outline around sprites that have +256 in their flags
and a drop shadow for sprites with +512 (see `SPRITE`), shifted by `dx`
(0–7) and `dy` (1–7, default 2,2). With `b` = 1 the bitmap casts a shadow
too. `INK` or `INK 0` switches it off. Example under [Sprites](#sprites).

### LOOK [0]

See [Workshop data](#workshop-data). `LOOK 0` is also the quick way back to
the start colours, no glow, no ink and the built-in font.

## Sprites

32 sprites of 16×16 pixels (32×32 when doubled), each with 15 colours plus
transparent. There is no limit per row: all 32 can stand on the same line.
Sprite 0 is in front, sprite 31 at the back. The 128 patterns (shapes) are
shared by all sprites.

**`LOAD` clears all patterns** (it brings in the workshop data of the new
program instead). So a program defines its patterns itself with `PATTERN`
– or paint them in the workshop and `SAVE` the program, then they come
along in the file. In the workshop, **B** writes painted patterns into the
program as `DATA` lines (see the README).

### PATTERN m,row,"pixels"

Row `row` (0–15) of pattern `m` (0–127): 16 characters, one hex digit per
pixel (`1`–`F`), `.` or `0` is transparent. The pixel value plus 16 × the
sprite's palette bank gives the colour, so with bank 0 the values are the
text colours: `7` is yellow, `B` dark grey.

### SPRITE n,x,y[,m[,f]] / SPRITE n

Shows sprite `n` (0–31) at screen position x,y (its top left corner; the
screen is 320×240, a sprite may stand partly outside) with pattern `m`.
Without `m` and `f` the sprite keeps them – `SPRITE n,x,y` just moves it.
`SPRITE n` alone hides it.

`f` adds up:

| f | |
|---|---|
| 0–15 | palette bank: colours bank × 16 + pixel value |
| +16 | mirrored left–right |
| +32 | mirrored upside down |
| +64 | behind the bitmap |
| +128 | double size (32×32) |
| +256 | outline in the `INK` colour |
| +512 | drop shadow in the `INK` colour |

The first `SPRITE` after power-on or after a machine program hides all
others and clears their settings.

```basic
10 FOR Z=0 TO 15:READ A$:PATTERN 0,Z,A$:NEXT
20 FOR X=-16 TO 320 STEP 2:SPRITE 0,X,100,0,0:PAUSE 1:NEXT
30 SPRITE 0
100 DATA ......7777......,....77777777....
110 DATA ...7777777777...,..777777777777..
120 DATA .77777777777777.,.777BB7777BB777.
130 DATA 7777BB7777BB7777,7777777777777777
140 DATA 7777777777777777,777B77777777B777
150 DATA .777B777777B777.,.7777BBBBBB7777.
160 DATA ..777777777777..,...7777777777...
170 DATA ....77777777....,......7777......
```

### HIT(n)

−1 (true) when sprite `n` has touched another sprite since the last time
you asked, otherwise 0. Asking clears the flag of this sprite only.

Two smileys: sprite 1 doubled with white outline and shadow, sprite 0 in
palette bank 2 (orange shades) passing through it. Keep lines 10 and
100–170 from above and replace 20–30:

```basic
20 INK 1,2,2:B=0
30 SPRITE 1,160,100,0,128+256+512
40 FOR X=0 TO 200 STEP 2:SPRITE 0,X,108,0,2:PAUSE 1
50 IF HIT(0) THEN B=B+1
60 NEXT
70 SPRITE 0:SPRITE 1:INK:PRINT B;"FRAMES TOUCHING"
```

## Workshop data

What you paint in the workshop (F1–F6) – patterns, tiles, two maps,
sounds, look and font – is saved with the program (`SAVE "GAME"`) and
comes back with `LOAD "GAME"`. These commands use it in the program.
To try them, load the demo game and keep its data:

```basic
LOAD "GLOWMINE"
NEW
10 LOOK:MAP 1:MAP 2
20 FOR X=0 TO 192 STEP 2:MAP 2,X,0:MAP 1,X/2,0:PAUSE 1:NEXT
30 SFX 1:T=TILE(2,10,20):TILE 2,10,20,0
40 PAUSE 60:PRINT "TILE WAS";T;"NOW";TILE(2,10,20)
RUN
```

(`NEW` removes the program but keeps the workshop data – a second `LOAD`
would replace it.) Map 2 scrolls at full speed, map 1 behind it at half
speed; line 30 plays sound 1 and takes a coin out of the map.

### MAP l[,x,y] / MAP 0

Layer `l` shows map `l` from the workshop: map 1 at the back instead of the
text, map 2 in front instead of the bitmap. A map is 64×32 tiles of 8×8
pixels (512×256); `x` (0–511) and `y` (0–255) scroll it by pixels. Tile
colour 0 is transparent. `MAP 0` switches maps off. When BASIC waits for a
command again, the layers show text and bitmap by themselves – so you
always see your listing.

### TILE l,x,y,t[,f] / TILE(l,x,y)

`TILE` puts tile `t` (0–255) into cell x (0–63), y (0–31) of map `l` (1 or
2). `f` = palette bank + 16 mirrored left–right + 32 upside down; without
`f` the tile keeps the bank it was painted in. `TILE(l,x,y)` returns the
tile in that cell (0 = empty, also outside the map) – for walls, floors,
coins.

### SFX n[,v] / SFX -1[,v]

Plays sound `n` (0–63) from the workshop in the background on voice `v`
(1–4). Without `v` it takes the first free voice from 4 down. `SFX -1`
stops all sounds, `SFX -1,v` only voice `v`. A sound has its voice for
itself while it plays – `PLAY` and `SONG` on the same voice get in its way.

### LOOK / LOOK 0

`LOOK` takes over the workshop's look: its palette, the glowing colours
and their strength, the ink and its font. `LOOK 0` goes back to the start
colours, no glow, no ink and the built-in font.

## Sound and music

The sound chip has 4 synth voices (1–4) and 8 sample channels (0–7). Sounds
play on while BASIC goes on.

### SOUND v,hz[,w]

A note on voice `v` (1–4) with frequency `hz` (1–3906) and waveform `w`:
1 triangle (default), 2 sawtooth, 3 pulse, 4 noise. The note sounds
until `SOUND v,0` lets it fade out (or `SILENCE`).

```basic
10 FOR F=200 TO 1200 STEP 20:SOUND 1,F,2:PAUSE 1:NEXT
20 SOUND 1,0
30 SOUND 1,262:SOUND 2,330:SOUND 3,392:PAUSE 60:SILENCE
```

### SILENCE

All voices and sample channels off; it also stops `PLAY`.

### SAMPLE k[,adr,len[,hz[,vol[,loop]]]] / SAMPLE k

Plays `len` bytes from `adr` on sample channel `k` (0–7): 8-bit samples
with sign (−128…127, stored as 0–255), at `hz` samples per second (default
22 050), volume `vol` 0–63 (default 63). With `loop` not 0 it repeats
until `SAMPLE k`. Samples may lie in expansion memory and be up to 16 MB
long; `tools/sample2mer.py` turns a sound file into one for `BLOAD`.

A beep from 32 bytes of sine wave (22 050 / 32 = 689 Hz):

```basic
10 A=262144
20 FOR I=0 TO 31:POKE A+I,127*SIN(I*3.14159/16) AND 255:NEXT
30 SAMPLE 0,A,32,22050,63,1
40 PAUSE 60:SAMPLE 0
```

### PLAY "notes"[,v]

Plays a melody in the background on voice `v` (1–4, default 1); each voice
has its own string. An empty string silences the voice. Capitals or small
letters, spaces don't matter:

| | |
|---|---|
| `C D E F G A B` | a note; then `#` or `+` sharp, `-` flat, a length and `.` for dotted |
| `R` | a rest, length as for notes |
| length | 1 whole, 2 half, 4 quarter, 8, 16, 32 …, also 3, 6, 12 |
| `O n`  `<`  `>` | octave 0–7 (start 4), one down, one up |
| `L n` | length for notes without one (start 4) |
| `T n` | tempo in quarter notes per minute, 32–255 (start 120) |
| `W n` | waveform 1 triangle, 2 sawtooth, 3 pulse, 4 noise |
| `V n` | volume 0–15 |
| `!` | start again (endless loop) |

```basic
10 PLAY "T140 W2 O4 L8 CDEFGAB>C",1
20 PLAY "T140 W1 O2 L2 CG",2
30 PRINT "MUSIC RUNS, BASIC TOO"
```

`PLAY "T150 W3 O5 L8 CEGEC<G>CE !"` plays a figure until `SILENCE`.

### SONG "name"[,drive] / SONG STOP / SONG(n)

Loads a song from the TAKTSTOCK tracker (`NAME.TAK`) and plays it in the
background, endlessly, with everything the tracker can do – eight tracks,
effects, envelopes. `SONG STOP` or `SILENCE` stop it. While a song plays,
it has all voices and sample channels. `SONG(n)`: 0 position in the song
order, 1 row (0–63), 2 playing (1) or not (0) – for games and demos that
follow the music. A file that is not a song gives `?NOT A SONG ERROR`.

```basic
SONG "NEBEL":PRINT SONG(0);SONG(1);SONG(2)
SONG "NEBEL":WHILE SONG(0)<2:WEND:PRINT "PART 3"
SONG STOP
```

(`NEBEL.TAK` is on the demo disk.)

## Input

### KEY(c)

−1 while the key with character `c` is held down, otherwise 0: letters as
capital or small letter code (`KEY(65)` or `KEY(97)` for A), 13 Return,
32 space, 28 right, 29 left, 30 up, 31 down. `KEY(0)`: any key. Unlike
`GET` it sees keys held together – for games.

Return is still down for a moment after you type `RUN` – don't use
`KEY(13)` to leave a program right at its start.

### JOY(n)

Joystick `n` (1 or 2) as the sum of: 1 right, 2 left, 4 down, 8 up,
16 fire A, 32 B, 64 C, 128 D, 256 start, 512 select. Test one bit with
`AND`: `IF JOY(1) AND 16 THEN …`.

A square moved with the cursor keys or joystick 1, space ends:

```basic
10 FOR Z=0 TO 15:PATTERN 0,Z,"7777777777777777":NEXT
20 X=152:Y=112
30 X=X-2*KEY(28)+2*KEY(29):Y=Y+2*KEY(30)-2*KEY(31)
40 J=JOY(1):X=X-2*((J AND 1)>0)+2*((J AND 2)>0)
50 SPRITE 0,X,Y,0,0:PAUSE 1
60 IF NOT KEY(32) THEN 30
70 SPRITE 0
```

(`KEY` is −1 when pressed, so `X-2*KEY(28)` adds 2. A comparison is −1 when
true, too.)

### MOUSE 1[,n] / MOUSE 0 / MOUSE(n)

`MOUSE 1` shows the mouse pointer: an arrow on sprite `n` (default 0) with
pattern 127. `MOUSE 0` hides it. `MOUSE(n)`: 0 x (0–319), 1 y (0–239),
2 buttons (1 left, 2 right, 4 middle, added up), 3 wheel.

A small paint program – left button draws, right button clears, space
ends:

```basic
10 GRAPHIC 1:MOUSE 1:OX=MOUSE(0):OY=MOUSE(1)
20 X=MOUSE(0):Y=MOUSE(1)
30 IF MOUSE(2) AND 1 THEN LINE OX,OY,X,Y,7
40 OX=X:OY=Y
50 IF MOUSE(2) AND 2 THEN GRAPHIC 1
60 IF NOT KEY(32) THEN 20
70 MOUSE 0:GRAPHIC 0
```

## Time

### PAUSE n

Waits `n` frames (0–255): 1/60 s each with the OSD's *Video* set to NTSC
(the default), 1/50 s with PAL. `PAUSE 1` in a game loop keeps it in step
with the picture.

### CLOCK(n)

The real-time clock: 0 frame counter, 1 second, 2 minute, 3 hour, 4 day,
5 month, 6 year, 7 weekday (0 = Sunday). The time comes from the MiSTer.

```basic
10 PRINT "IT IS";CLOCK(3);":";CLOCK(2);":";CLOCK(1)
20 PRINT "DATE";CLOCK(4);".";CLOCK(5);".";CLOCK(6)
30 T=CLOCK(0):PAUSE 60:PRINT CLOCK(0)-T;"FRAMES LATER"
```

## Program flow

### IF … THEN … ELSE …

`ELSE` belongs to the closest `IF` before it in the same line. BASIC puts a
`:` in front of `ELSE` when you type it (`LIST` shows it). `IF A THEN 100
ELSE 200` jumps.

### WHILE condition … WEND

Repeats while the condition is true – also across lines, nested. When the
condition is false right away, the program goes on after the matching
`WEND`.

### REPEAT … UNTIL condition

Repeats until the condition is true; the loop runs at least once. A
`RETURN` may leave a subroutine from inside either loop.

```basic
10 INPUT "A NUMBER";N
20 IF N<0 THEN PRINT "NEGATIVE":ELSE PRINT "ZERO OR MORE"
30 I=1:WHILE I<=N:PRINT I;:I=I*2:WEND:PRINT
40 REPEAT:D=INT(RND(1)*6)+1:PRINT D;:UNTIL D=6:PRINT
```

### RENUMBER [new[,step[,from]]]

Renumbers the lines from line `from` (default: the first) as `new`,
`new+step` … (default 10, 10). All references follow: `GOTO`, `GOSUB`,
`THEN`, `ELSE`, `RUN`, `ON … GOTO/GOSUB`. A reference to a line that does
not exist stops it before anything changes (`?UNDEF'D STATEMENT ERROR IN
line`). It clears the variables.

```basic
RENUMBER 100,5
```

## Drives and files

| Drive | |
|---|---|
| 1, 2 | the disk images chosen in the OSD (*Drive 1*, *Drive 2*), FAT16 |
| 3 | the folder `games/MERIDIAN/files` on the SD card or a USB drive – needs the network service (README) |
| 0 | the save memory of an inserted cartridge, when it has been set up as a disk (HORIZONT does that) |

File names are 8.3: up to 8 letters A–Z, digits, `_` and `-`, then an
ending. Commands add the usual ending when you leave it out. Each command
takes an optional drive number at the end; without it the `DRIVE` is used.

### DRIVE n

The drive for commands without a drive number (0–3, start 1).

### DIR [drive]

Lists the files with their sizes and the free space.

### SAVE "name"[,drive] / LOAD "name"[,drive]

Saves the program as `NAME.BAS` – together with everything in the workshop
that is not empty – and loads it back. `LOAD` replaces program **and**
workshop data.

### SAVE / LOAD (without a name)

Puts the program aside in expansion memory and fetches it back – a quick
copy before you try something risky.

```basic
SAVE
NEW
LOAD
LOAD "R20",3
```

### BSAVE "name",adr,length[,drive] / BLOAD "name"[,adr[,drive]]

`BSAVE` saves memory as a MER file (`NAME.MER`, with its load address in a
16-byte header). `BLOAD` loads it back to that address, or to `adr`. Both
take 24-bit addresses. Saving and loading the whole bitmap:

```basic
10 GRAPHIC 1
20 FOR I=0 TO 99:LINE RND(1)*320,RND(1)*240,RND(1)*320,RND(1)*240,RND(1)*255:NEXT
30 BSAVE "PICTURE",131072,76800
40 GRAPHIC 1:PAUSE 60
50 BLOAD "PICTURE":PAUSE 120:GRAPHIC 0
```

### SCRATCH "name"[,drive]

Deletes a file (ending `.BAS` when none is given): `SCRATCH
"PICTURE.MER"`.

### HEADER "name"[,drive]

Sets the disk image up anew (FAT16) with the disk label `name` –
**everything on it is gone**. Not on drive 3.

## Network

`NET` needs the network service on the MiSTer's Linux side (see the
README). Errors never stop the program; `NET(0)` and `NET$(0)` tell you
what happened.

### NET "command"[,channel]

| command | |
|---|---|
| `GET url` | fetch a web page (http or https); its lines arrive on the channel |
| `FETCH url [adr]` | fetch a file into memory (MER files to their address and start them) |
| `CONNECT host[:port]` | TCP connection on channel 1–4 (port 23 when none is given) |
| `LISTEN port` | wait for a call (chat, two-player games) |
| `SEND text` | send a line |
| `CLOSE` | close the connection |
| `DISK name [mb]` | a new empty disk image in `games/MERIDIAN` (default 8 MB) |
| `FILES` | the files in `games/MERIDIAN` (as lines on `NET$(0)`) |
| `HELP` | the list |

### NET(k) / NET$(k)

`NET(0)`: status of the last command (0 fine, an HTTP code, negative for an
error). `NET(k)` for k = 1–4: lines waiting on channel k (0 none, −1 no
connection, −2 waiting for a call). `NET$(k)`: the next line from channel
k (`""` when none); `NET$(0)` is the message of the last command, then its
further lines.

```basic
NET "GET wttr.in/Berlin?format=3":PRINT NET(0):PRINT NET$(0):PRINT NET$(0)
```

prints `200`, `HTTP 200, 1 LINES` and the weather. A chat over TCP:
`programme/chat.bas` (`CHAT.BAS` on the demo disk).

## Memory and machine code

### PEEK(adr) / POKE adr,value / WAIT adr,mask[,xor]

24-bit addresses: below 65 536 is bank 0 (system, screen, chips), above it
the rest of the 16 MB.

| Address | |
|---|---|
| 1024–3423 | text screen in MODE 40: 2 bytes per character – the character code, then the colour (text + 16 × background); MODE 80 up to 5823 |
| 18 432–47 103 | bank 0, free for machine code (`$4800–$B7FF`; SONG uses the last 896 bytes while it plays) |
| 65 536–131 071 | bank 1: the BASIC program and its variables |
| 131 072–207 871 | the bitmap of `GRAPHIC`, 320 bytes per row |
| 262 144–1 048 575 | expansion memory free for your data (banks `$04–$0F`) |

```basic
POKE 262144,42:PRINT PEEK(262144)
POKE 1104,65:POKE 1105,7
```

The second line puts a yellow-on-black `A` at the start of row 2. The
chips' registers (`$C000–$CFFF`) and the rest of the memory map are in
`KONZEPT.md`.

### FRE(0)

Free bytes for program and variables.

### USR(x)

Calls machine code in bank 0 at the address in bytes 96/97 (low, high). It
runs in the 65C816's 6502 emulation mode with data bank 1 and returns with
`RTS`; long addressing (opcodes `$AF`, `$8F` …) reaches every bank. This
one writes `*` to the top left corner of the screen (`LDA #$2A`,
`STA $000400`, `RTS`):

```basic
10 FOR I=0 TO 6:READ B:POKE 18432+I,B:NEXT
20 POKE 96,0:POKE 97,72:X=USR(0)
30 DATA 169,42,143,0,4,0,96
```

For larger programs: write them in the monitor, with an assembler on a
computer and `tools/senden.py` (README), or `BLOAD` them.

### MONITOR

The machine-code monitor with assembler, disassembler and single step
(README). `X` goes back to BASIC.

## Error messages

Besides Microsoft's messages, MERIDIAN BASIC knows: `?FILE NOT FOUND`,
`?DISK FULL`, `?NO DISK`, `?BAD DISK`, `?WRITE PROTECTED`,
`?DIRECTORY FULL`, `?FILE TOO BIG`, `?BAD FILE NAME`, `?WEND WITHOUT WHILE`,
`?WHILE WITHOUT WEND`, `?UNTIL WITHOUT REPEAT` and `?NOT A SONG` (each with
`ERROR`). A value outside its range (a colour above 255, sprite 32 …) gives
`?ILLEGAL QUANTITY ERROR`.

## All MERIDIAN words at a glance

| Word | | Word | |
|---|---|---|---|
| `BLIT` | copy memory | `MODE` | 40 or 80 columns |
| `BLOAD` | load a file into memory | `MONITOR` | machine-code monitor |
| `BSAVE` | save memory as a file | `MOUSE` / `MOUSE()` | pointer on/off / position, buttons |
| `CLOCK()` | clock and frame counter | `NET` / `NET()` / `NET$()` | network |
| `CLS` | clear the text screen | `PALETTE` | mix a colour |
| `COLOR` | text and background colour | `PATTERN` | one row of a sprite pattern |
| `DIR` | list the files | `PAUSE` | wait frames |
| `DRIVE` | default drive | `PLAY` | music in the background |
| `ELSE` | with `IF` | `PLOT` | set a pixel |
| `GLOW` | glowing colours | `RENUMBER` | renumber lines |
| `GRADIENT` | background gradient | `REPEAT` … `UNTIL` | loop |
| `GRAPHIC` | bitmap on/off | `SAMPLE` | play a sample |
| `HEADER` | format a disk | `SCRATCH` | delete a file |
| `HIT()` | sprite collision | `SFX` | workshop sound |
| `INK` | outline and shadow | `SHINE` | smooth colour gradients |
| `JOY()` | joystick | `SILENCE` | all sound off |
| `KEY()` | key held down | `SONG` / `SONG()` | tracker song |
| `LINE` | draw a line | `SOUND` | a note |
| `LOOK` | workshop look | `SPRITE` | show and move a sprite |
| `MAP` | show a workshop map | `STAMP` | put a picture into the bitmap |
| | | `TILE` / `TILE()` | set / read a map cell |
| | | `WHILE` … `WEND` | loop |

`LOAD`, `SAVE`, `PEEK`, `POKE`, `WAIT` and `FRE` are Microsoft's, with the
extensions described above.
