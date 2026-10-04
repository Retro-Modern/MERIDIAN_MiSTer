10 rem *** regenbogen - meridian 816 basic ***
20 cls:graphic 1
30 for x=0 to 319 step 2
40 line 160,239,x,0,16+x*.75
50 sound 1,200+x*2,1:pause 1
60 next:sound 1,0
70 for a=0 to 6.29 step .01
80 plot 160+120*sin(a*3),110+90*cos(a*2),1
90 next
100 sound 1,523,1:sound 2,659,1:sound 3,784,1
110 pause 90:silence
