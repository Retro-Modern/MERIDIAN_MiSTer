# Pruefstand fuer den NMI im CPU-Kern: make && ./obj_dir/tb_nmi
K = ../../rtl/cpu65c816
CPU = $(K)/P65C816_pkg.sv $(K)/P65C816.sv $(K)/mcode.sv $(K)/AddrGen.sv $(K)/ALU.sv \
      $(K)/AddSubBCD.sv $(K)/BCDAdder.v $(K)/adder4.v $(K)/bit_adder.v

obj_dir/tb_nmi: $(CPU) tb_nmi.cpp
	verilator --cc --exe --build -j 8 -O2 -Wno-fatal -Wno-lint -Wno-style -Wno-MULTIDRIVEN \
		-Wno-LATCH --top-module P65C816 -o tb_nmi $(CPU) tb_nmi.cpp

clean:
	rm -rf obj_dir
