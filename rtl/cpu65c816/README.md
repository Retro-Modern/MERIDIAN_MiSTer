# P65C816 — 65C816 CPU core

A SystemVerilog conversion of the VHDL 65C816 CPU core written by
**srg320** for [SNES_MiSTer](https://github.com/MiSTer-devel/SNES_MiSTer),
with modifications for the Apple IIgs.

## Provenance

The original core is the `P65C816` VHDL implementation in
`rtl/CPU/` of SNES_MiSTer (`P65C816.vhd`, `AddrGen.vhd`, `ALU.vhd`,
`AddSubBCD.vhd`, `BCDAdder.vhd`, `MCode.vhd`, `P65816_pkg.vhd`).
Those files were translated to SystemVerilog/Verilog, preserving the
microcode-driven structure and the cycle-level bus behaviour, and then
extended for this core's needs.

Upstream: https://github.com/MiSTer-devel/SNES_MiSTer
Author:   srg320 — https://github.com/srg320

## Changes from the original

- Translated from VHDL to SystemVerilog / Verilog.
- `ABORT_N` handling and the `VPA`/`VDA`/`VPB`/`MLB` bus-status outputs are
  exercised by the Apple IIgs memory controller, which needs them to
  distinguish opcode fetches, data cycles and vector pulls for shadowing
  and language-card decode.
- Timing adjusted for the IIgs FPI/Mega II bus: the core is driven by a
  clock enable (`CE`) and stalled via `RDY_IN` so the memory controller
  can insert the IIgs's RAM-refresh and slow-bus stretch cycles.
- Assorted fixes found while running the Apple IIgs ROM self-tests and
  the 65C816 instruction-level test suites.

## Files

| File | Role |
|------|------|
| `P65C816.sv` | Top level: state machine, registers, bus interface |
| `P65C816_pkg.sv` | Shared types and microcode record definitions |
| `mcode.sv` | Microcode ROM — decodes opcode to control signals |
| `AddrGen.sv` | Effective-address generation |
| `ALU.sv` | Arithmetic/logic unit |
| `AddSubBCD.sv` | Binary and BCD add/subtract |
| `BCDAdder.v` | BCD adder used by `AddSubBCD` |
| `adder4.v`, `bit_adder.v` | Adder primitives |
| `65C816.qip` | Quartus file list for this directory |

## License

GPL-3.0-or-later, inherited from SNES_MiSTer. See `LICENSE` in this
directory for the full text.
