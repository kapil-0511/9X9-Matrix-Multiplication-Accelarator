# 9×9 Tiled Matrix Multiplier — RTL Design

A fully synthesizable hardware accelerator for 9×9 signed integer matrix multiplication, implemented in Verilog and verified with a SystemVerilog testbench on Xilinx Artix-7 FPGA using Vivado XSim.

---

## Overview

Computes **C = A × B** where A, B, C are 9×9 matrices of 32-bit signed integers.

A compact **3×3 systolic PE array** is reused across **27 tile operations** (9 output tiles × 3 accumulation steps each) to complete the full 9×9 multiplication. All data is stored in a single on-chip SRAM and accessed through an **AMBA APB slave interface**.

---

## Architecture

```
         APB Master (host)
               |
         apb_slave.v        ← address decode, CSR (ctrl/status)
               |
         Arbiter (top)      ← busy ? tile_controller : apb_slave
               |
         sram.v             ← 256×32-bit synchronous SRAM
          /         \
   tile_controller.v    ← tiling FSM, SRAM access, partial-sum accumulation
         |
   mac_array_3x3.v     ← 3×3 systolic PE array (weight-stationary)
         |
       pe.v × 9        ← registered MAC + nearest-neighbour pass-through
```

---

## File Structure

```
matmul_9x9/
├── rtl/
│   ├── sram.v                # 256×32 synchronous SRAM (1-cycle read latency)
│   ├── pe.v                  # Systolic processing element: MAC + a_out/b_out pass-through
│   ├── mac_array_3x3.v       # 3×3 systolic array, diagonal wavefront skewing
│   ├── tile_controller.v     # Tiling FSM: load A/B tiles, fire MAC, write-back C
│   ├── apb_slave.v           # AMBA APB v2.0 slave, address decode, control/status
│   └── matmul_top.v          # Top-level: wires all modules + SRAM bus arbiter
├── tb/
│   └── tb_matmul.sv          # SystemVerilog testbench — 10 randomised test cases
├── setup_project.tcl          # Creates and configures the Vivado project from scratch
└── README.md
```

---

## Register Map

| Address  | Register   | Access | Bits              | Description                        |
|----------|------------|--------|-------------------|------------------------------------|
| `0x000`–`0x143` | Matrix A | R/W | [31:0] | 81 × 32-bit signed elements, row-major |
| `0x200`–`0x343` | Matrix B | R/W | [31:0] | 81 × 32-bit signed elements, row-major |
| `0x400`–`0x543` | Matrix C | R    | [31:0] | 81 × 32-bit result elements, row-major |
| `0x600`  | Control    | W      | `[0]` = start     | Write `0x1` to start multiplication   |
| `0x604`  | Status     | R      | `[0]` = done, `[1]` = busy | Poll until `done=1`        |

Element address formula: `base + (row * 9 + col) * 4`

---

## Software Flow

```
1.  Write A  →  APB write to 0x000 + offset*4   (81 writes)
2.  Write B  →  APB write to 0x200 + offset*4   (81 writes)
3.  Start    →  APB write 0x00000001 to 0x600
4.  Poll     →  APB read 0x604 until bit[0] = 1 (done)
5.  Read C   →  APB read from 0x400 + offset*4  (81 reads)
```

---

## Systolic Array Design

The 3×3 PE array uses a **weight-stationary, diagonal wavefront** dataflow:

- A operands enter from the **left edge** and flow right across each row
- B operands enter from the **top edge** and flow down each column
- Each PE accumulates `c_acc += a_in * b_in` every cycle and passes operands to its right/bottom neighbour

**Wavefront skewing** delays row `i` of A by `i` cycles and column `j` of B by `j` cycles, ensuring `A[i][k]` and `B[k][j]` arrive at `PE[i][j]` in the same clock cycle:

```
cyc = 1        : PE clear (reset c_acc for new tile)
cyc = 2..8     : data feed (7 cycles — covers max skew of i+j+k = 2+2+2)
cyc = 9        : done asserted
```

Interconnect is **purely nearest-neighbour** — no broadcast buses.

---

## Tiling Strategy

The 9×9 multiplication is decomposed with loop order **br → bc → bk** (output-stationary):

```
for br = 0..2          // output tile row
  for bc = 0..2        // output tile col
    clear C_acc
    for bk = 0..2      // contraction (accumulation) dimension
      C[br][bc] += A[br][bk] × B[bk][bc]   // 3×3 systolic tile multiply
    write C[br][bc] to SRAM
```

Total: **27 MAC operations** per full 9×9 multiply.

---

## SRAM Layout

| Region | Address Range | SRAM Offset |
|--------|---------------|-------------|
| A      | 0x000–0x143   | 0 – 80      |
| B      | 0x200–0x343   | 81 – 161    |
| C      | 0x400–0x543   | 162 – 242   |

Element `M[row][col]` maps to SRAM address: `base_offset + row*9 + col`
(implemented as `(row<<3) + row + col` — shift-add, no multiplier).

---

## Design Parameters

| Parameter | Value | Notes |
|-----------|-------|-------|
| Matrix size | 9×9 | Fixed |
| Tile size | 3×3 | PE array dimension |
| Data width (DW) | 32-bit signed | Operand and result width |
| Accumulator width (AW) | 64-bit signed | Prevents intermediate overflow |
| SRAM depth | 256 words | Holds A + B + C (243 words used) |
| APB address width | 12-bit | `paddr[11:0]` |
| Clock | 100 MHz (10 ns) | Testbench `always #5` |
| Target FPGA | xc7a35tcpg236-1 | Artix-7 35T |
| Tile latency | 8 cycles | 1 clear + 7 data |

---

## Running Simulation

### Option 1 — Vivado GUI

1. Create the project (first time only):
   ```
   vivado -mode batch -source setup_project.tcl
   ```
2. Open the project:
   ```
   vivado vivado_proj/matmul_9x9.xpr
   ```
3. In the Vivado GUI: **Flow → Run Simulation → Run Behavioral Simulation**
4. In the Tcl console:
   ```tcl
   source tb_matmul.tcl
   ```

### Option 2 — Vivado Tcl Console (project already open)

```tcl
launch_simulation
run all
```

### Option 3 — Command Line (xvlog/xelab/xsim)

```bash
cd sim
xvlog --incr --relax -prj tb_matmul_vlog.prj
xelab --debug typical -top tb_matmul -snapshot tb_matmul_behav
xsim tb_matmul_behav -tclbatch tb_matmul.tcl
```

---

## Testbench

The testbench (`tb/tb_matmul.sv`) runs **10 test cases** with escalating value ranges. Both A and B are filled with independent random values using `$urandom_range`, guaranteeing a mix of positive and negative operands.

| Test | Range       | Max \|result element\| |
|------|-------------|------------------------|
| T01  | ±10         | 900                    |
| T02  | ±20         | 3,600                  |
| T03  | ±50         | 22,500                 |
| T04  | ±100        | 90,000                 |
| T05  | ±150        | 202,500                |
| T06  | ±200        | 360,000                |
| T07  | ±300        | 810,000                |
| T08  | ±500        | 2,250,000              |
| T09  | ±750        | 5,062,500              |
| T10  | ±1000       | 9,000,000              |

All results fit within 32-bit signed range (max ≈ 2.1 billion). The 64-bit internal accumulator prevents overflow during partial-sum accumulation.

Each test:
1. Loads A and B via APB writes
2. Asserts start via APB write to `0x600`
3. Polls `0x604` until done
4. Reads C matrix back via APB
5. Compares every element against a 64-bit software golden model
6. Prints A, B, C_dut, and C_ref matrices with pass/fail per element

**Expected result: 810 PASS | 0 FAIL**

---

## APB Protocol Notes

- `pready` is **permanently asserted** (zero-wait-state slave) — every transaction completes in one ACCESS cycle
- `pslverr` is permanently deasserted — no error response
- Read latency: SRAM address is driven combinationally in SETUP phase; `rdata` is valid in ACCESS phase (1-cycle SRAM latency is absorbed by the SETUP→ACCESS transition)
- `start` is a combinational pulse — asserted only during the single ACCESS cycle of a write to `0x600`

---

## Signed Arithmetic

- Operands are stored as 32-bit two's complement in SRAM
- All MAC operations use `$signed()` casts throughout the PE and tile controller
- 64-bit accumulator in each PE holds up to 9 products of 32-bit × 32-bit without overflow
- Write-back to SRAM truncates accumulator to lower 32 bits (safe for all test value ranges)
