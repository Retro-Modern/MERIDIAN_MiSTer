10 rem *** abend - der pinsel-look von meridian 1.0 ***
20 rem shine: verlaeufe, glow: leuchten, ink: kontur und schatten
30 cls:graphic 1:color 1,0
40 for y=0 to 131:line 0,y,319,y,128:next
50 for y=132 to 239:line 0,y,319,y,129:next
60 shine 128,0,1,1,4:shine 128,60,4,2,8:shine 128,105,12,5,8:shine 128,131,15,11,6
70 shine 129,132,11,5,8:shine 129,190,3,2,7:shine 129,239,1,1,2
75 shine 99,158,5,10,6:shine 99,239,1,3,2:shine 157,100,10,7,14:shine 157,131,15,10,11
80 for i=1 to 70:plot rnd(1)*320,rnd(1)*95,47:next
90 for d=-12 to 12:w=sqr(144-d*d):line 252-w,38+d,252+w,38+d,207:next
100 plot 248,34,205:plot 249,35,205:plot 256,42,205:plot 255,43,205:plot 246,42,205
110 for x=0 to 319:h=110+9*sin(x/31)+5*sin(x/13)
120 c=154:if 9/31*cos(x/31)+5/13*cos(x/13)<0 then c=157
130 line x,h,x,131,c:line x,132,x,132+(132-h)*.8,146:next
140 for x=0 to 170:line x,158+(x/165)^2*85,x,239,99:next
150 for y=141 to 172:line 26,y,84,y,59:next
160 for y=122 to 141:w=(y-122)*1.85+2:line 55-w,y,55+w,y,212:next
170 for y=148 to 159:line 32,y,41,y,46:line 48,y,57,y,46:next
180 line 36,148,36,159,57:line 52,148,52,159,57:line 32,153,57,153,57
190 for y=153 to 172:line 64,y,74,y,57:next
200 line 63,144,73,144,237:line 63,145,73,145,237
210 for y=200 to 203:line 140,y,238,y,58:next
220 for x=146 to 236 step 22:line x,204,x,222,57:line x+1,204,x+1,222,57:next
230 line 229,172,229,199,183:line 230,172,230,199,183
240 for y=170 to 176:line 226,y,233,y,47:next
250 for i=0 to 15:read a$:pattern 0,i,a$:next
260 sprite 0,177,168,0,128+256+512
270 ink 144,2,2
280 glow 9,7,46,47,207,237
290 goto 290
300 data "......9999......",".....999999.....","...9999999999...","......AAAA......"
310 data "......ABAA......","......AAAA......",".....666666.....","....66666666.77."
320 data "....66666666.77.","....6.6666.6.CC.","....6.6666.6....","......6666......"
330 data "......B..B......","......B..B......","......B..B......",".....99..99....."
