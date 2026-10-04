10 rem *** starfall - meridian 816 basic ***
20 dim sx(5),sy(5),sv(5)
30 cls:graphic 1:gradient 0,0,0,1,239,4,0,7
40 for i=1 to 70:plot rnd(1)*320,rnd(1)*200,15:next
50 restore:for i=0 to 15:read a$:pattern 1,i,a$:next
60 for i=0 to 15:read a$:pattern 2,i,a$:next
70 print:print "          *** STARFALL ***":print
80 print "     catch the falling stars!":print
90 print "  move: mouse, joystick or cursor keys"
100 print "  start: click, fire or space":print
110 print "  you have 60 seconds.":mouse 1
120 play "t150 w3 v8 o5 l8 cegec<g>ce dfafd<a>df egbge<b>eg fa>c<agb>d<b !",1
130 play "t150 w2 v10 o3 l4 ccgg ddaa eebb ffgg !",2
140 b=mouse(2) or key(32) or (joy(1) and 16):if b=0 then 140
150 mouse 0:cls:for k=1 to 5:gosub 500:sy(k)=sy(k)-k*45:next
160 x=152:mo=mouse(0):s=0:cf=0:tl=60:fr=60:t0=clock(0)
170 gosub 650
200 m=mouse(0):if m<>mo then x=m-8:mo=m
210 j=joy(1):if key(29) or (j and 2) then x=x-5
220 if key(28) or (j and 1) then x=x+5
230 if x<0 then x=0
240 if x>304 then x=304
250 sprite 0,x,212,1
260 for k=1 to 5:sy(k)=sy(k)+sv(k):sprite k,sx(k),sy(k),2
270 h=hit(k):if h and sy(k)>196 and sy(k)<226 then gosub 600
280 if sy(k)>240 then gosub 500
290 next:if cf then cf=cf-1:if cf=0 then sound 4,0
300 if clock(0)-t0>=fr then gosub 700
310 if tl>0 then pause 1:goto 200
320 silence:for k=0 to 5:sprite k:next
330 print chr$(1):print:print:print "             game over":print
340 print "        stars caught:";s:print
350 mi=clock(2):print "        played at ";right$(str$(clock(3)),2);":";right$(str$(100+mi),2)
360 print:print "   click or press space to play again"
370 pause 60
380 b=mouse(2) or key(32) or (joy(1) and 16):if b=0 then 380
390 goto 30
500 sx(k)=8+rnd(1)*296:sy(k)=-16-rnd(1)*12:sv(k)=1.5+rnd(1)*2+s/15:return
600 s=s+1:cf=8:sound 4,600+s*25,3:gosub 500
610 gosub 650:return
650 print chr$(1);" stars:";s;tab(28);"time:";tl;" ":return
700 fr=fr+60:tl=tl-1:goto 650
800 rem basket
810 data "................","................"
820 data "................","................"
830 data "................","................"
840 data "8..............8","88............88"
850 data "9888888888888889","9989898989898999"
860 data ".99898989898999.","..998989898999.."
870 data "...9999999999...","................"
880 data "................","................"
890 rem star
900 data ".......7........",".......7........"
910 data "......777.......","......717......."
920 data ".....77177......","7777771117777777"
930 data ".77111111111777.","..77111111177..."
940 data "...771111177....","....7111117....."
950 data "....7111117.....","...771777177...."
960 data "...777...777....","..777.....777..."
970 data "..7.........7...","................"
