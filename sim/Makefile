# Simulation des MERIDIAN-Kerns: make && ./obj_dir/meridian_sim 1 out 0 5 30
CPU = ../rtl/cpu65c816/P65C816_pkg.sv ../rtl/cpu65c816/P65C816.sv ../rtl/cpu65c816/mcode.sv \
      ../rtl/cpu65c816/AddrGen.sv ../rtl/cpu65c816/ALU.sv ../rtl/cpu65c816/AddSubBCD.sv \
      ../rtl/cpu65c816/BCDAdder.v ../rtl/cpu65c816/adder4.v ../rtl/cpu65c816/bit_adder.v
RTL = ../rtl/meridian_core.sv ../rtl/kobold.sv ../rtl/pinsel.sv ../rtl/pforte.sv ../rtl/bote.sv ../rtl/orgel.sv ../rtl/kran.sv ../rtl/lotse.sv ../rtl/zusatz.sv ../rtl/truhe.sv ../rtl/draht.sv

obj_dir/meridian_sim: $(CPU) $(RTL) ../rom/kern.hex ../rom/basic.hex ../rom/dos.hex ../rom/song.hex ../rom/werkstatt.hex tb.cpp
	verilator --cc --exe --build -j 8 -O3 --x-assign fast --x-initial fast \
		-Wno-fatal -Wno-lint -Wno-style -Wno-MULTIDRIVEN -Wno-LATCH \
		-GROM_FILE='"../rom/kern.hex"' -GBASIC_FILE='"../rom/basic.hex"' -GDOS_FILE='"../rom/dos.hex"' -GSONG_FILE='"../rom/song.hex"' -GWERK_FILE='"../rom/werkstatt.hex"' --top-module meridian_core \
		-o meridian_sim $(CPU) $(RTL) tb.cpp

clean:
	rm -rf obj_dir out
