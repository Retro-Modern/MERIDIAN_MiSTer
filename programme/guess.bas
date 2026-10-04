10 rem *** guess - else, while, repeat (stage 13) ***
20 cls:print "      *** guess the number ***":print
30 x=rnd(-clock(0)):n=int(rnd(1)*100)+1:t=0
40 print "i am thinking of a number from 1 to 100."
50 repeat
60 input "your guess";g:t=t+1
70 if g<n then print "  higher!" else if g>n then print "  lower!"
80 until g=n
90 print:print "right after";t;"tries."
100 if t<=7 then print "well played!" else print "binary search needs 7 at most."
110 print:print "the collatz path of";n;":"
120 c=n:s=0
130 while c<>1
140 if c and 1 then c=3*c+1 else c=c/2
150 print c;:s=s+1
160 wend
170 print:print "1 reached after";s;"steps."
