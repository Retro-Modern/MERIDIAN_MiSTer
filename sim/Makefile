# Simulation des MERIDIAN-Kerns: make && ./obj_dir/meridian_sim 1 out 0 5 30
#
# make profil: einmal mit Messpunkten bauen, die buchstabenprobe darauf laufen
# lassen (gut eine Minute, braucht die Amiga-Werkstatt) und danach mit diesem
# Profil uebersetzen (clang PGO). Der Simulator rechnet dann rund 11 %
# schneller, Bild fuer Bild gleich. Das Profil liegt in obj_profil/ und gilt,
# bis make clean es loescht; ohne Profil baut make wie zuvor. Nach groesseren
# Aenderungen am RTL lohnt ein neues make profil (ein altes stoert nicht, es
# hilft nur weniger).
CPU = ../rtl/cpu65c816/P65C816_pkg.sv ../rtl/cpu65c816/P65C816.sv ../rtl/cpu65c816/mcode.sv \
      ../rtl/cpu65c816/AddrGen.sv ../rtl/cpu65c816/ALU.sv ../rtl/cpu65c816/AddSubBCD.sv \
      ../rtl/cpu65c816/BCDAdder.v ../rtl/cpu65c816/adder4.v ../rtl/cpu65c816/bit_adder.v
RTL = ../rtl/meridian_core.sv ../rtl/kobold.sv ../rtl/pinsel.sv ../rtl/pforte.sv ../rtl/bote.sv ../rtl/orgel.sv ../rtl/kran.sv ../rtl/lotse.sv ../rtl/zusatz.sv ../rtl/truhe.sv ../rtl/draht.sv
VERILATOR = verilator --cc --exe --build -j 8 -O3 --x-assign fast --x-initial fast \
	-Wno-fatal -Wno-lint -Wno-style -Wno-MULTIDRIVEN -Wno-LATCH \
	-GROM_FILE='"../rom/kern.hex"' -GBASIC_FILE='"../rom/basic.hex"' -GDOS_FILE='"../rom/dos.hex"' -GSONG_FILE='"../rom/song.hex"' -GWERK_FILE='"../rom/werkstatt.hex"' --top-module meridian_core
PROFIL = obj_profil/meridian.profdata
PYTHON = $(HOME)/Claude/amiga-fabula/werkstatt/.venv/bin/python
ifneq ($(wildcard $(PROFIL)),)
PGO = -CFLAGS "-fprofile-instr-use=$(CURDIR)/$(PROFIL) -Wno-profile-instr-out-of-date -Wno-profile-instr-unprofiled"
endif

obj_dir/meridian_sim: $(CPU) $(RTL) ../rom/kern.hex ../rom/basic.hex ../rom/dos.hex ../rom/song.hex ../rom/werkstatt.hex tb.cpp $(wildcard $(PROFIL))
	$(VERILATOR) $(PGO) -o meridian_sim $(CPU) $(RTL) tb.cpp

profil:
	rm -rf obj_profil
	$(VERILATOR) --Mdir obj_profil -CFLAGS -fprofile-instr-generate -LDFLAGS -fprofile-instr-generate \
		-o meridian_sim $(CPU) $(RTL) tb.cpp
	cd ../fabula && LLVM_PROFILE_FILE=$(CURDIR)/obj_profil/lauf_%p.profraw \
		MERIDIAN_SIM=$(CURDIR)/obj_profil/meridian_sim $(PYTHON) buchstabenprobe.py
	xcrun llvm-profdata merge -output=$(PROFIL) obj_profil/lauf_*.profraw
	rm -rf obj_dir
	$(MAKE) obj_dir/meridian_sim

clean:
	rm -rf obj_dir obj_profil out

.PHONY: profil clean
