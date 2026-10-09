10 c=0:xt=0:v=0:x=0:m1=0:m2=0:j=0:yt=0:u=0:g=0:p=0:a=0:n1=0:n2=0:l1=0:r1=0:l2=0:r2=0:h1=0:h2=0:fb=0:w=0:y=0:f=0:vt=0:vu=0:tf=0:yf=0:o=0:t=0
20 ba=.5:bb=1.375:bc=.375:bd=1.625:q=0:s=2.5:e2=.3125:br=1.8125:bl=.0625:k=.65:e=.125:be=.25:h=.5
25 fr=0:fl=0:nc=0:mn=0:lv=0:rem die haeufigsten variablen zuerst: basic sucht sie der reihe nach
30 dim z(255),d(15),mx(39),my(39)
40 rem *** glowmine - ein spiel aus der werkstatt (meridian 1.0) ***
50 rem sprites, kacheln, karten, klaenge, look und zeichensatz: f1-f6
60 for i=1 to 18:z(i)=1:next:for i=32 to 34:z(i)=2:next:z(40)=8:z(41)=4:z(42)=4
70 for i=50 to 55:z(i)=16:next:for i=0 to 15:d(i)=int(6*sin(i*.3927)+.5):next
80 read mn:for i=1 to mn:read mx(i),my(i):next:read a,a1,h1,l1,r1,a2,h2,l2,r2,dx,dy,sx,sy
90 fr=13+256+512:fl=fr+16:fb=10+256+512:fz=2+128+256+512
100 rem --- titel ---
110 sfx -1:silence:map 0:for i=0 to 31:sprite i:next
120 look:color 7,0:cls:shine:shine 0,0,1,0,3:shine 0,150,2,0,4:shine 0,239,6,1,0
130 for i=1 to 9:print:next
140 print "       COLLECT ALL THE GOLD AND":print "         FIND THE WAY OUT!":print:print
150 color 15:print "     ARROWS OR JOYSTICK:  RUN":print "     SPACE, UP OR FIRE:   JUMP":print
160 print "     MIND THE BATS AND THE LAVA.":for i=1 to 4:print:next:color 7
170 print "          PRESS SPACE OR FIRE":for i=1 to 4:print:next:color 12
180 print "  SPRITES, TILES, MAPS, SOUNDS, LOOK":print "   AND FONT: PRESS F1-F6 AFTER ESC";
190 sprite 0,40,150,0,fr+128:sprite 1,248,148,8,fb+128
200 play "t110 w3 v8 o5 e8d8c8o4b8a4e4 o5f8e8d8c8o4b4g4 a8b8o5c8d8e4a4 g8f8e8d8e2 !",1
210 play "t110 w1 v12 o2 l4 a>a<a>a< f>f<g>g< a>a<f>f< g>g<e>e< !",2
220 t=clock(0)
230 repeat:i=i+1 and 15:for a=0 to 7:sprite 3+a,24+a*34,20+d(i+a and 15),32+a,fz:next
240 sprite 1,248,148,8+(i and 4),fb+128:get k$:repeat:until clock(0)>=t:t=clock(0)+3
250 until key(32) or (joy(1) and 16)
260 rem --- spiel ---
270 play "",1:play "",2:for a=0 to 10:sprite a:next:cls
280 for a=1 to mn:tile 2,mx(a),my(a),40:next
290 for b=0 to 2:for a=0 to 1:tile 2,dx+a,dy+b,44+b*2+a:next:next
300 x=sx:y=sy:kx=x:ky=y:w=0:g=0:v=0:nc=0:lv=3:q=0:o=-1:f=fr:xt=x*e:yt=y*e
310 m1=a1:m2=a2:n1=1.5:n2=-1.5:gosub 800:sprite 20,6,2,26,2+256
320 for a=0 to 2:sprite 23+a,262+a*18,2,27,1+256:next
330 map 1,0,0:map 2,0,0:sfx 8,1:a=hit(0):t=clock(0):tz=t
340 repeat
350 j=joy(1):if key(0) then get k$:j=j or -key(28) or -2*key(29) or -8*key(30) or -16*key(32)
360 v=0:vt=0:if j and 1 then v=s:vt=e2:vu=br:tf=ba:f=fr
370 if j and 2 then v=-s:vt=-e2:vu=bl:tf=bb:f=fl
380 if v then u=xt+vu:if (z(tile(2,u,yt+bc)) or z(tile(2,u,yt+bd))) and 1 then v=0:vt=0
390 x=x+v:xt=xt+vt:if g then 440
400 w=w+k:if w>6 then w=6
410 y=y+w:yt=y*e:if w<0 then u=yt+be:if (z(tile(2,xt+ba,u)) or z(tile(2,xt+bb,u))) and 1 then y=int(u)*8+6:yt=y*e:w=0
420 if w>0 then u=yt+2:a=z(tile(2,xt+ba,u)) or z(tile(2,xt+bb,u)):if a then gosub 600
430 goto 460
440 if v then if (z(tile(2,xt+tf,yf)) and 3)=0 then g=0:w=0
450 if j and 24 then if g then g=0:w=-6.5:sfx 0,4
460 a=tile(2,xt+1,yt+1):if z(a)>7 then gosub 650
470 c=x-152:if c<0 then c=0
480 if c>192 then c=192
490 if c<>o then map 2,c:map 1,c*h:o=c
500 p=3:if g then p=0:if v then p=1+(x and 4)
510 sprite 0,x-c,y,p,f
520 m1=m1+n1:if m1<l1 or m1>r1 then n1=-n1
530 sprite 1,m1-c,h1+d(m1 and 15),8+(m1 and 4),fb
540 m2=m2+n2:if m2<l2 or m2>r2 then n2=-n2
550 sprite 2,m2-c,h2+d(m2 and 15),8+(m2 and 4),fb
560 if hit(0) then gosub 700
570 repeat:until clock(0)>=t:t=t+2
580 until q
590 goto 900
600 rem landen: fels, planke (nur von oben), lava
610 if a and 4 then 700
620 if (a and 3)=0 then return
630 n=int(u)*8:if (a and 1)=0 then if y-w+16>n then return
640 y=n-16:yt=y*e:yf=yt+2:w=0:g=1:sfx 4,4:if a and 1 then if x>kx+96 then kx=x:ky=y
645 return
650 rem muenze oder offene tuer
660 if z(a)=16 then q=2:return
670 tile 2,xt+1,yt+1,0:nc=nc+1:sfx 1,3:gosub 800:if nc=mn then gosub 850
680 return
700 rem getroffen
710 sfx -1:sfx 2,4:w=-5
720 repeat:y=y+w:w=w+.5:sprite 0,x-c,y,2,f:pause 1:until y>250
730 lv=lv-1:sprite 23+lv:if lv=0 then q=1:return
740 x=kx:y=ky:xt=x*e:yt=y*e:w=0:g=0:pause 30:a=hit(0):sfx 8,1:t=clock(0):return
800 a=mn-nc:b=int(a/10):sprite 21,26,6,16+b,2+256:sprite 22,34,6,16+a-b*10,2+256:return
850 for b=0 to 2:for a=0 to 1:tile 2,dx+a,dy+b,50+b*2+a:next:next:sfx 3,3:return
900 rem --- ende ---
910 sfx -1:map 0:for a=0 to 31:sprite a:next:cls:tz=int((clock(0)-tz)/60):pause 30
920 for a=1 to 10:print:next:color 7
930 if q=2 then print "         YOU FOUND THE WAY OUT!":print:print "        ALL";mn;"PIECES OF GOLD IN";tz;"S":sfx 5,4
940 if q=1 then print "              GAME OVER":print:print "          GOLD:";nc;"OF";mn
950 color 12:print:print:print:print "          PRESS SPACE OR FIRE":pause 60
960 repeat:get k$:until key(32) or (joy(1) and 16):goto 100
9000 data 30,2,11,3,11,4,11,18,11,19,11,57,11,58,11,53
9010 data 14,54,14,3,17,4,17,5,17,28,17,33,17,47,17,48
9020 data 17,49,17,30,19,31,19,10,20,11,20,12,20,42,20,43
9030 data 20,25,21,26,21,35,21,53,23,54,23,56,23
9040 data 2,208,120,168,280,400,80,352,440
9050 data 59,9,32,176
