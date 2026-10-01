# L3CtlClone — RTL → GDS interview kit

You owned **L3CtlClone** from **RTL to GDS**. Use **only** dumped facts in interviews.

**Do not mix** the BK LAC core sheet (N3E, 3.4 GHz, 2.65 mm², 0.945 V SS) into L3CtlClone unless you state it is the same chip/node.

## Given

| Item | Value |
|---|---|
| Block | **L3CtlClone** |
| Node | **N7** (7 nm FinFET) |
| Meaning (say this, don’t invent more) | **L3 control, cloned instance** — control/pipeline around L3, a **replicated** PD block, not “the whole SRAM cache” unless you later say it included arrays |
| Operating corners | **ttop**, **ttop9v**, **tt1p2v** |

### How to read the corners (from the names only)

| Corner | What you can defend | What you must not claim |
|---|---|---|
| **ttop** | **TT**, typical process, **operating-point** voltage (nominal “op”) | Exact volts until you dump them |
| **ttop9v** | **TT at 0.9 V** | That 0.9 V is Vmin or Fmax |
| **tt1p2v** | **TT at 1.2 V** | That 1.2 V is a typical **N7 core-only** rail without a dual-rail/IO story |

All three names are **TT** (typical-typical). That is an **implementation / power-typical** set, not a full **SS setup + FF hold** foundry deck. Interviewers will ask: *where did SS/FF live?*

**N7 + 0.9 V + 1.2 V:** 0.9 V is a plausible **N7 logic** operating point. **1.2 V** is **high** for 7 nm core FinFET — treat as a **second rail or high-voltage mode** until you dump UPF (always-on, IO, analog, SRAM, overdrive). Do not invent which.

This block is **N7**, not the BK **N3E** LAC core. Two projects/nodes if both appear on the resume.

---

## 90-second opener (current facts only)

> I owned **L3CtlClone** from **RTL to GDS** in **N7**. It is the **L3 control clone** — a replicated control block in the L3 hierarchy. I implemented it at three **TT** operating corners: **ttop**, **ttop9v** (TT **0.9 V**), and **tt1p2v** (TT **1.2 V**). At 7 nm that means **one netlist across a 0.9 V logic-like point and a 1.2 V high rail**, plus nominal ttop: delay, hold, and IR all move with voltage. Clone means **floorplan, pins, and timing budget must be repeatable**. These were the **block operating corners**, not a full SS/FF foundry deck. This is **N7**, not the N3E 3.4 GHz core.

Add frequency, area, arrays, ttop voltage, and challenges when dumped.

---

# Project BK — L3 cache PD (RTL → GDS)

You owned this block **from RTL to GDS**. That is a **full-chip-quality** story: constraints, netlist, floorplan, clocks, memories, STA, IR, PV, GDS. Do not reduce it to “I ran Innovus.”

**BK CPU spec (LAC, 3.4 GHz, 2.65 mm², N3E) is a different sheet.** L3CtlClone is **N7**. Do not claim 3.4 GHz or N3E on L3CtlClone.

## Still needed (dump when ready)

```text
L3CtlClone RAW
- Foundry / metal stack / cell height:
- Area, util, instances, macros (control-only vs SRAMs):
- Frequency; why a clone (how many copies, top-level):
- What ttop voltage actually is:
- What 1.2 V supplies (core overdrive vs SRAM vs IO vs AON):
- SS/FF / hold corners if any beyond ttop, ttop9v, tt1p2v:
- Challenges (one at a time):
```

---

## How L3 PD is not core PD

| Core (LAC, 3.4 GHz) | L3 (your block) |
|---|---|
| Period **294 ps**, EX/bypass | Often **slower clock** or **multi-cycle array**; still huge **bus RC** |
| Std-cell timing cone, some RF/L1 | **80%+ area macros** if it is a real L3 |
| H-tree skew vs ALU | H-tree + **per-bank clocks / ICG / gated arrays** |
| ELVT for Fmax | Mix: **array compiler Vt**, **wrapper LVT/ULVT**, leakage of **idle banks** |
| Pin access of flops | **SRAM pin pitch, decoder side, burst data** |
| One hotspot EX | **Many PG holes**, **bank-wise IR**, **wake di/dt** |

Interview sentence: *On L3 I optimized **array assembly and data-spine RC**. On the core I would optimize **294 ps FO4**. Same node, different cost function.*

---

## RTL → GDS (study this order today)

### 1. RTL, architecture, SDC

**What you must be able to draw:** slices/banks, tag vs data, directory, pipe stages (request, tag-lookup, data-return), fill/evict, snoop/coherence if present, CSR/APB.

**Q. What did you take from RTL before floorplan?**  
**A.** Clock list and **generated clocks** (dividers, BIST). **False/multi-cycle** on array internals vs **wrapper**. Bus widths (data, tag, ECC). **Reset and scan**. **Which paths are 1-cycle** (hit data return vs tag). I do not floorplan before I know **which SRAM port sits on the 1-cycle path**.

**Q. Who owned SDC?**  
**A.** If you owned RTL→GDS: **you** freeze SDC with design. L3 is full of **MCYC on SRAM clk-to-Q + decode** that are only legal if the **pipe says so**. Waiving tag-hit because “memory is slow” is a **functional fail**.

### 2. SRAM compiler, views, wrappers

**Q. What views does each L3 SRAM need?**  
**A.** **LEF** (pins, blockage, PG), **LIB** (setup/hold, clk-to-Q, power) per **PVT**, **GDS**, **LVS netlist**, **behavior/Verilog**, **MBIST/repair** pins, **EM/IR current**. Mismatch between **LEF pin** and **LIB arc** is a late STA bomb.

**Q. Why a wrapper?**  
**A.** Clock gate, isolation, **BIST mux**, **repair/redundancy**, ECC, pipeline flops, LS if array voltage ≠ logic. Wrapper is **std-cell timing** around a **hard block**. Most L3 WNS is **wrapper + spine**, not inside the bitcell.

**Q. Compiler mux vs banking?**  
**A.** Fat SRAM: fewer instances, **horrible pin density**, **PG hole**. Banked: more channels, **better access**, more **CTS leaves** and **abutment DRC**. L3 almost always **banks + data spine**.

### 3. DFT / MBIST / repair (you cannot skip this if you owned GDS)

**Q. How does MBIST change PD?**  
**A.** Extra **muxes on every array port** (timing + congestion). **BIST clocks** (often OCC / async to functional). **Repair chains** and fuses. **Retention/bypass**. Scan through wrappers. I close **shift, capture, BIST, functional** as **modes**, not “DFT later.”

**Q. Lockup / domain crossing into L3?**  
**A.** Functional L3 clk vs **scan vs BIST**. Lockups at **clock-domain** boundaries. Hold at **FF 1.05 V** (BK sheet) through **BIST mux min-path** is a classic tapeout.

### 4. Floorplan (this is the L3 interview)

**Q. Why not push all L3 SRAMs to the edges?**  
**A.** L3 **is** macros — but **ports still have to meet the controller and the fabric**. If you glue **data pins to the block edge or to another array**, you get **no approach**, **thin channels**, **repeaters in slivers**, **H-tree taps blocked**, **PG straps cut**. I **abut same-orientation banks** with a **legal pin-side channel**, **controller in the spine**, **feedthroughs** reserved for top-level. Edge is for **cluster interface**, not for burying **data-out**.

**Q. Draw a defensible L3 floorplan.**  
**A.** (Whiteboard.) Data arrays in **rows/cols by bank**, **pin sides facing a data spine**. Tag/directory **closer to control** (often more timing-critical, smaller). Controller / pipe / BIST in **center or T-spine**. **Keep-out + halo** per compiler. **PG grid continuous over channels**, straps **around** (not through) array interiors. **H-tree trunks M14–M15** with **via farms in channels**, not over **metal-blocked SRAM**.

**Q. Utilization looks low. Why is L3 still hard?**  
**A.** **Std-cell util in leftover slivers** can be 90% while **block util is 50%**. Congestion is **channel and pin**, not core density. Interviewers who say “just grow the channel” need to hear **area, latency, and IR**.

### 5. Power intent

**Q. 0.765 V and 0.80 V on L3?**  
**A.** Same trap as BK: **rails vs Fmax corners**. SRAM compilers often **want their own VDD_array**. Dual rail: **LS, isolation, switch daisy-chain, inrush**. If L3 can **light-sleep / shutdown banks**: **retention pins, clamp, wake IR**. I would not copy the core 0.945 V setup story onto L3 without the **L3 SDC**.

### 6. Synthesis → place

**Q. What is special in L3 synth?**  
**A.** Don’t unroll **wide buses** into **random logic** that fights SRAM pin order. **Preserve bus structure**, **physical hierarchy** matching banks. High-fanout: **bank clocks, enables, reset, BIST**. Spines need **pipelining** if RTL didn’t: that’s an **RTL ECO**, not a buffer tree miracle.

**Q. Placement?**  
**A.** Bounds per bank wrapper. **Don’t let buffers wander onto array tops** (blockage). Path groups: **tag 1-cycle**, **data return**, **fill**. Congestion: **pin access M2 P34** at SRAM. Useful skew only with **hold budget** through wrappers.

### 7. CTS (H-tree on M14–M15, L3 flavor)

**Q. How do you CTS L3 vs core?**  
**A.** Same **H-tree metals** if the program spec says M14–M15. L3 has **many ICG / per-bank enables** and **BIST clocks**. I build **functional H-tree**, then **gating at leaves**, **not** a second wild tree per bank that **destroys skew**. Latency can be large; **multi-cycle paths must match RTL**. Local skew **inside a bank wrapper** matters for **hold**.

**Q. Clock on top of SRAM?**  
**A.** Arrays **block** clock routing and **vias**. Trunks in **channels / over controller**. Shielded **NDR**. Mesh is **not** on the BK sheet — don’t say mesh.

### 8. Route, SI, EM

**Q. Wide L3 data bus SI?**  
**A.** Hundreds of bits, **same-layer run**, **fill/evict**. Coupling → **setup and hold**. Spread, shield critical strobes, **layer-assign to P76**, **via pillars**. EM on **repeatedly switching fill buses and clocks**, not only PG.

### 9. STA / MCMM

**Q. Typical L3 violating paths?**  
**A.** **Tag hit → data enable**, **SRAM clk-to-Q + wrapper + spine flop**, **ECC**, **snoop**, **MCYC exceptions that are wrong**, **BIST mux left in functional path**. Debug order: **mode/corner → clock → exception → mem timing model → SI → IR**.

**Q. Hold?**  
**A.** Short wrapper paths, **FF Cbest**, **ELVT buffers**, **useful skew**, **BIST mux**. Filler/decap around arrays **changes** hold. BK sheet hold is **1.05 V 125 °C** — still ask **cold + scan**.

### 10. IR / EM / thermal

**Q. L3 IR pattern?**  
**A.** Arrays are **PG holes**. Current in **periphery + controller**. **Wake of many banks** is **di/dt**. **SHDMIM** in channels. **UTRDL** from top. Wordline peak inside compiler is **IP signoff**; **your** job is **rail to the pins**. Leakage of **idle L3** at **TT 0.75 V** still matters even if functional Fmax is a different voltage.

### 11. PV → GDS

**Q. What breaks LVS on L3?**  
**A.** **Wrong SRAM abstract vs GDS**, **repair fuse**, **MIM**, **tap/well around compilers**, **filler in keep-out**, **PG pin name vs LEF**. DRC: **density over arrays**, **color/via**, **antenna on long buses**, **min-area after ECO**.

**Q. GDS ownership?**  
**A.** Merge **std-cell + SRAM GDS + filler + metal fill**, **map layers**, **stream out**, **signoff DRC/LVS/antenna**, **dummy fill vs timing**. RTL→GDS means you **carried the golden database**, not that you clicked one button.

### 12. ECO

**Q. Metal-only on L3?**  
**A.** Can fix **spine buffers, layer, some hold**. Cannot **move an SRAM** or **add a pipe stage**. Spares in **controller and channels**, not on **array tops**. Late timing on **tag 1-cycle** often needs **RTL**.

---

## L3CtlClone — Q&A from given corners

### Q1. What was the block?

**A.** **L3CtlClone**: L3 **control** path, **cloned** (replicated) in physical hierarchy. I owned it **RTL to GDS**. Clone means **identical abstract, pins, PG, clock, and timing budget** for every copy — a **methodology** problem, not only a PPA problem.

### Q2. What does “Clone” change in PD?

**A.** Floorplan and **pin order** must **abut or feed through** the same way at top. You cannot “nudge one macro for timing” on copy A and leave copy B. **CTS latency** and **boundary budgets** are contracts. A late ECO must be **clone-legal** or you **break identical abstracts**.

### Q3. Why is it Ctl, not the whole L3?

**A.** Control is **std-cell heavy** (request pipe, hit/miss, queues, CSR) sitting **next to arrays** that may live in another partition. Timing is **control-to-array pins** and **clone-to-fabric**. If arrays were not in this block, I will say so when I dump macros — I will not claim I compiled the L3 SRAMs unless I did.

### Q4. Explain ttop, ttop9v, tt1p2v.

**A.** Three **TT** operating corners: **nominal op**, **0.9 V**, **1.2 V**. I used them as the **block operating set**. **0.9 V** is the **slow-TT** delay/IR stress among these three; **1.2 V** is **fast-TT** (hold, leak, EM, short-path). **ttop** is the **intended typical**. I timed **the same GDS** into all three, not three different netlists.

### Q5. Only TT — is that signoff?

**A.** Honest answer: **those were the operating corners for L3CtlClone.** Full CMOS signoff is usually **SS setup + FF hold + RC corners + SI**. If the program timed clones at TT only, I say that and I know the **risk**: TT hides **setup at SS** and **hold at FF**. If SS/FF were at top-level, I say **block vs chip** signoff. I do **not** pretend ttop9v is SSGNP.

### Q6. 0.9 V and 1.2 V on one control block. What do you close?

**A.**  
- **0.9 V TT**: **setup**, drive, **IR drop → delay**, max-tran/cap.  
- **1.2 V TT**: **hold**, min-pulse, **leakage**, **EM**, SI speedup.  
- **ttop**: **power/typical delay** and the corner you quote to architecture.  
Sizing that fixes 0.9 V setup **hurts 1.2 V hold**. That is the **Vt/size** loop on this block.

### Q7. N7 with 0.9 V and 1.2 V — explain.

**A.** **L3CtlClone is N7, 7 nm FinFET.** **ttop9v** is TT **0.9 V** — a normal **N7 logic-class** voltage. **tt1p2v** is TT **1.2 V** — **high** for 7 nm core; I treat it as a **second operating voltage or rail** (I do not invent IO vs SRAM vs overdrive). Same GDS, two voltages: **0.9 V setup/IR**, **1.2 V hold/EM/leak**. This is **not** the N3E BK core (0.765/0.80, 0.945 setup).

### Q7b. What does N7 change in PD vs planar / vs N3E?

**A.** **N7:** FinFET (quantized width), **multi-patterning** on lower metals, BEOL RC starts to dominate, Vt flavors, pin access. **Vs N3E (other project):** N3E is **more EUV, tighter pitch, LVF, 3.4 GHz / 294 ps core**. I will not mix metal stacks, cells, or frequencies across the two. On **L3CtlClone** I talk **N7 + clone + ttop/0.9/1.2**.

### Q8. MCMM for a clone?

**A.** Modes: **functional, scan, maybe BIST**. Corners: **ttop / ttop9v / tt1p2v**. Constraints must **not** be corner-specific hacks that make **0.9 V green** and **1.2 V** a waiver mess. Clone abstracts: **ILM/ETM or .lib** generated **per corner**.

### Q9. IR at these corners?

**A.** **IR% at 0.9 V** is worse for **function and delay**. **Current at 1.2 V** is worse for **EM and overshoot**. I would not size PG only at ttop.

### Q10. Trap question: “So you signed off typical only?”

**A.** *I implemented L3CtlClone at the three TT operating corners specified for that block: ttop, 0.9 V, and 1.2 V. That covers **voltage-mode typical**. I can discuss what was done at **top-level SS/FF** or **why the methodology used TT** — I will not rebrand TT as SS.*

---

## Extra interview questions (practice out loud)

1. Walk RTL→GDS for L3 in **8 steps** with **what can fail** at each.  
2. Tag vs data array: **which is closer to the controller and why?**  
3. How you **sized a channel** (pin count × pitch × layers × via).  
4. Functional vs BIST clock: **one tree or two?**  
5. ECC on the critical path — **fix in PD or RTL?**  
6. How L3 **feedthroughs** affect **top-level BK** timing.  
7. **Retention** and **isolation** at 0.765/0.80 V.  
8. Why **LEF blockage** vs **placement blockage** vs **route halo**.  
9. **Compiler EM** vs **your strap EM**.  
10. A **DRC** you only see after **dummy fill** on SRAM roofs.

---

## Whiteboard (do these today)

1. **Banked L3**: 4×N arrays, data spine, tag cluster, controller, H-tree taps in channels.  
2. **1-cycle tag path** through wrapper + SRAM model.  
3. **PG** around two abutted SRAMs (hole, via, MIM).  
4. **RTL→GDS flowchart** with **owners** (you vs CAD vs DFT vs compiler).

---

## Trap list (L3)

- Claiming **N3E / 3.4 GHz** on **L3CtlClone** — this block is **N7**.  
- Calling **ttop9v / tt1p2v** an SS/FF deck.  
- Saying **1.2 V is a normal N7 core-only VDD** without a rail story.  
- “L3 is easy because it is slower / full of macros.”  
- Pushing **all** arrays to the edge.  
- Ignoring **MBIST mux** in functional timing.  
- CTS **over SRAM tops**.  
- **GDS** = “Calibre was green” with no **abstract vs layout** story.

---

## Today’s drill (45–60 min)

1. Say the **90-second opener** twice (record yourself).  
2. Draw the **floorplan** and explain **one channel**.  
3. Answer **Q wrapper**, **Q MBIST**, **Q H-tree vs SRAM blockage**.  
4. Write **three numbers you still need** (freq, area, SRAM count) and dump them next.
