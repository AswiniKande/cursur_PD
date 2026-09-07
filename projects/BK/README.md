# Project BK — High-performance CPU (interview kit)

Update this file as numbers land. Interview answers must use **given** facts; anything in *Assumed / typical* is only for study, not for claiming on a resume.

## Given (use these)

| Item | Value |
|---|---|
| Project | BK |
| Design | High-performance CPU |
| Node | TSMC **N3E** (3 nm class, FinFET) |
| Frequency target | **3.4 GHz** |
| Area | **2.4 mm²** |
| Cycle time | **T = 1/3.4e9 ≈ 294 ps** |
| Characteristic size | √2.4 ≈ **1.55 mm** on a side if roughly square; ~1.5–2.2 mm of Manhattan span |

## Still needed (do not invent in interviews)

Role and ownership, instance count, util, metal stack / cell height, cache/SRAM map, clock architecture (tree vs mesh), voltage domains, MCMM/derate, WNS/TNS, IR, DFT, ECO, tapeout status, what you personally closed.

---

## 90-second interview opener (safe version)

> I worked physical design on **BK**, a **high-performance CPU** at **TSMC N3E**. The block is **2.4 mm²** with a **3.4 GHz** target, so the cycle is about **294 ps**. At this node and frequency the problem is not “run the flow.” It is **closing a ~300 ps period** across a **~1.5 mm** core: **clock latency and skew eat the budget**, **BEOL RC and pin access** dominate data paths, **L1/L2 macros** decide the floorplan, and **dynamic IR plus variation (LVF)** show up as Fmax, not as a DRC. My job was to treat floorplan, CTS, and signoff as one timing/power object, not three tools.

When you have ownership details, append one sentence: *I owned [floorplan / CTS / timing / IR] from [stage] through tapeout.*

---

## What this design point actually means

**294 ps is a CPU period, not a GPU/SoC period.**  
A few tens of picoseconds of extra clock latency, SI, or IR push-out is several percent of Fmax. Interviewers will expect you to talk in **picoseconds and millivolts**, not “we optimized PPA.”

**2.4 mm² is a core-class floorplan.**  
This is a **CPU core / complex**, not a full SoC. Expect **RF/SRAM** (L1 I/D, TLB, L2 slice), **control irregularity**, and **hotspot current density**. Macro placement is the chip.

**N3E is FinFET, EUV-heavy, RC- and variation-dominated.**  
Std-cell delay is quantized (fins). Long nets lose to **wire + via**. Signoff is **POCV/LVF**, SI-aware, multi-voltage if turbo/Vmin exist. Hold at FF is as hard as setup at SS because **min paths are short** and **derate is large**.

**Clock is a first-class datapath.**  
On a 1.55 mm block at 3.4 GHz, a naive tree can spend **a large fraction of 294 ps** in insertion delay. HPC CPUs often use **mesh or hybrid mesh**, **NDR clocks on upper metal**, **useful skew**, and **tight local-skew regions** (ALU vs L1 vs L2).

**Power grid is an Fmax feature.**  
CPU current is spiky (clock edge + issue width). Dynamic drop on a clock spine or execution cluster **adds delay in the same corner you advertise 3.4 GHz**. Floorplan PG, via density, and decap are timing closure.

---

## Floorplan stance (BK-specific)

Do **not** push L1/L2 and register-file macros to the edges by default. On BK, the critical paths are **reg–reg in the EX/INT cluster**, **reg–mem into L1**, and **L2 interface**. Edge-parking those memories **adds RC on the 294 ps budget**, **creates channels** that trap buffers, and **pulls the clock** to the perimeter. Put **pin sides toward the logic that owns Fmax**, sit macros on a **thick PG mesh**, size **explicit channels**, keep **PHY/analog/IO** on the true edge if present.

---

## Question bank (answer with BK numbers)

### Q1. Walk me through BK.

**A.** BK is an HPC **CPU** at **N3E**, **2.4 mm²**, **3.4 GHz → 294 ps**. Span is ~1.55 mm. Closure is a **period problem**: clock, data RC, variation, and IR share one budget. Floorplan is cache/RF macros + EX datapath. CTS must keep **skew and latency** from eating Fmax. Signoff is MCMM + SI + LVF. *(Then: your role, one hard close.)*

### Q2. Why is 3.4 GHz on 2.4 mm² hard at N3E?

**A.** Because **T ≈ 294 ps** while **Manhattan span ~1.5 mm**. Wire delay, via stack, clock insertion, OCV/LVF, SI, and IR-induced push-out are the same order as **a few FO4**. You cannot “buffer out of it” without power and min-path hold. N3E libraries are fast but **BEOL and variation** set Fmax. Utilization looks fine while **pin access and cache ports** kill the period.

### Q3. What is your timing budget sketch?

**A.** (Whiteboard.)  
`Tck ≥ Tclk_q + Tpd + Tsu + clock_skew_effective + uncertainty + SI + IR_pushout + variation`.  
With Tck = 294 ps, if launch/capture clock **mismatch + uncertainty** is 20–40 ps and **Tsu** is ~10–20 ps, **combinational+wire** must fit in **~230–260 ps** before derate. That is why **useful skew**, **layer assignment**, and **not detouring around macros** matter. I would not quote a fake FO4 count unless I measured it on BK.

### Q4. Tree, mesh, or hybrid for BK?

**A.** At **3.4 GHz** on **~1.5 mm**, a **pure tree** often loses on **global skew and latency variation** across PVT. A **clock mesh** (or **hybrid: mesh over EX/L1, tree to quieter blocks**) buys **low skew** at the cost of **power and EM** on the mesh drivers. Decision: **skew sensitivity of the 294 ps paths** vs **clock power / IR**. I would CTS-prototype both on the real floorplan, not pick from a slide.

### Q5. Where do you put L1 and L2?

**A.** **L1** next to the pipes that use it (load/store, I-side fetch), **pin side inward**, **channel sized to port pitch**, **on strong PG** (fill + via). **L2** on the back of the core or a banked side **with a data spine**, not a wall on the pad edge unless the bus leaves the CPU there. Edge is for **cluster interface / debug / analog**, not for burying D-cache ports.

### Q6. Setup is green in PnR, Fmax is 3.1 GHz at signoff. Debug order?

**A.** (1) **Which corner/mode** — turbo vs Vmin, setup vs hold. (2) **Clock** — latency, local skew, generated clocks, ICG enable. (3) **Constraint quality** — false/MCYC/CDC. (4) **Parasitics + SI** — SPEF vs extract, coupling on EX loops. (5) **LVF/POCV vs PnR derate**. (6) **IR annotated delay**. (7) **Path class** — mem vs ALU vs bypass. Do not start with global upsizing; **294 ps** dies from **clock and exceptions** first.

### Q7. Hold at 3 nm / 3.4 GHz?

**A.** High-performance cells + **short EX bypass** + **useful skew** + **FF/low-temp min** + **SI speedup** + **LVF** → hold is a **tapeout item**, not a cleanup. Scan shift/capture hold is a second chip. Fix: **data delay on true min paths**, **clock skew control**, **not** random delay cells on everything (power, setup). Filler/decap and metal fill can **move hold** after you thought you were done.

### Q8. IR and 3.4 GHz?

**A.** CPU **di/dt** at the clock edge. Dynamic drop on the **mesh or ALU row** adds **delay in the 294 ps path** and can **starve SRAM wordline**. Static IR from macro PG holes is the floorplan bug. I would co-design **strap pitch, via pillars, decap, and CTS** and sign off with **vectors that toggle EX + L1**, not only vectorless.

### Q9. Congestion vs Fmax — which do you give?

**A.** On BK, **a clean route that detours the ALU–L1 net is a frequency fail**. I would **open a channel, move a macro, or pad a hotspot** rather than detour a 3.4 GHz loop. Congestion 0.95 in a **non-critical** corner can wait. Congestion on **EX bypass / cache fill** cannot.

### Q10. Multi-Vt / multi-channel at N3E?

**A.** **ULVT/LVT** in the 3.4 GHz cone, **SVT/HVT** on non-critical and min-path-safe control, **leakage vs Fmax** at the turbo corner. Fin count / drive is quantized — **sizing is discrete**. VT-swap is an ECO tool; **wrong VT on a hold path** is a respins.

### Q11. What does N3E change vs 7/5 nm PD?

**A.** More **EUV**, tighter **pin access**, **via/metal resistance** more of the path, **LVF** expected at signoff, **cell height / track** choices lock routing. Same CTS/STA story, **smaller absolute slack**. A 20 ps mistake was a warning at 2 GHz; here it is **~7% of the period**.

### Q12. Hierarchical or flat on 2.4 mm²?

**A.** A **2.4 mm² CPU** is often **flat or one-level** (core) with **cluster top** above. Hierarchical only if CAD/instance count or IP (L2, debug) forces it. Budgets at 294 ps are **dangerous** — ILM/ETM error is Fmax. If hierarchical, **pin timing and clock** are the contract, not area.

### Q13. DFT at this frequency?

**A.** OCC, scan **shift much slower than 3.4 GHz**, **capture** may still stress **hold**. Lockup latches, compression, and **memory BIST** around L1/L2 must not **wreck functional CTS**. I keep **scan exceptions honest** and close **shift/capture as real modes**, not leftover.

### Q14. Late ECO, 3.4 GHz, N3E — metal-only?

**A.** Metal-only can **buffer, layer-assign, some VT if spare**, not **rewrite an ALU path**. Spare cells must sit in **EX and cache-port channels**, not only in leftover corners. If the period is already packed, **base-layer ECO or RTL pipeline** is the honest answer.

### Q15. Behavioral: what would you not do on BK?

**A.** (Fill with your story.) Template: *I would not freeze a pretty macro ring before a 3.4 GHz path-group map. I would not CTS to a skew target that ignores LVF and IR. I would not waive a path I cannot defend with RTL.*

---

## Whiteboard drills (BK)

1. Draw **294 ps** setup/hold with launch/capture, OCV arrows, and 20 ps IR push-out.  
2. Sketch **2.4 mm²** core: L1I, L1D, RF, EX, L2 interface, clock spine/mesh, PG straps.  
3. Show **why L1D on the far edge** adds RC the period cannot afford.  
4. List **signoff corners** you would demand for a 3.4 GHz claim (even if you do not have the exact list yet).

---

## Trap list (do not say)

- Exact WNS/TNS, instance count, metal stack, or “we signed off LVF” until you have it.  
- “N3E is GAA” — **N3E is FinFET**; GAA is the next family (e.g. N2).  
- “2.4 mm² is the whole SoC.” It is **core-class**.  
- “3.4 GHz at all voltages.” Likely **turbo / high-V**; **Vmin Fmax** is a different number.  
- Command dumps (Innovus/ICC2) instead of **period, skew, IR, macros**.
