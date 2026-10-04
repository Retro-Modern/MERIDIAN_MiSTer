10 rem *** chat - meridian 816 basic ***
20 cls:print "        *** MERIDIAN CHAT ***":print
30 input "host (w = wait for a call)";h$
40 if h$="w" or h$="W" then net "listen 6502",1:goto 80
50 p$=":6502":for i=1 to len(h$):if mid$(h$,i,1)=":" then p$=""
60 next
70 net "connect "+h$+p$,1
80 print net$(0):if net(0)<0 then end
90 l$="":print
100 get k$:if k$<>"" then gosub 300
110 n=net(1):if n>0 then gosub 400:goto 110
120 if n=-1 then print:print "*** connection closed":end
130 goto 100
300 if k$=chr$(13) then net "send "+l$,1:print:l$="":return
310 if k$<>chr$(8) then 340
320 if len(l$)>0 then l$=left$(l$,len(l$)-1):print k$;
330 return
340 if len(l$)<70 then l$=l$+k$:print k$;
350 return
400 if pos(0) then print
410 color 7:print "> ";net$(1):color 14:print l$;:return
