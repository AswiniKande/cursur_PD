# Project BK — High-performance CPU (interview kit)

Facts below come from the BK **core (LAC)** spec table. Use them in interviews. Do not invent WNS, IR, instance count, or UPF topology.

**L3 is a separate block you owned RTL → GDS.** Do not paste 3.4 GHz / 2.65 mm² onto L3 until L3 specs are dumped. Study kit: [L3_RTL_to_GDS.md](L3_RTL_to_GDS.md).

## Specs (given)

| Item | Value |
|---|---|
| RTL | **LAC RTL** |
| Design | High-performance CPU |
| Frequency | **3.4 GHz** → **T ≈ 294 ps** |
| Power goal | **NA** (not a signoff number on this sheet) |
| Area | **2.65 mm²** → √2.65 ≈ **1.63 mm** on a side if square; ~1.6–2.3 mm Manhattan span |
| Node / library | **TSMC N3E** (FinFET, not GAA) |
| Cell | **H169PP54** (169 nm-class height, 54 nm poly pitch) |
| Metal stack | **15M** `1Xa1Xb1Xc1Xd1Ya1Yb4Y2Yy2Z` + **UTRDL** + **SHDMIM** |
| Pitches (from stack name) | M1 **P54**, M2 **P34**, M3 **P40**, M4 **P42**, M5 **P66**, M6–M11 **P76** |
| Signal routing | **M0–M13** |
| Clock | **H-tree on M14–M15** |
| Vt palette | **ELVT / ULVT / ULVTLL / LVT** (no SVT/HVT on this sheet; no multi-Lg) |
| Rails listed | **0.765 V and 0.80 V** |

### Corners on the sheet (functional)

| Use | Corner |
|---|---|
| Setup | `ssgnp_cworstccworstt_max_0p945v_125c` |
| Hold | `ffgnp_cbestccbestt_min_1p05v_125c` |
| Power | `tt_typical_max_0p75v_85c` |

Treat these as **the three named PVTs**, not as “full MCMM.” A 3.4 GHz N3E CPU almost always has more corners in the real signoff deck.

---

## 90-second opener

> I did physical design on **BK**, an HPC **CPU** (**LAC RTL**) at **TSMC N3E**. The block is **2.65 mm²**, cell **H169PP54**, **3.4 GHz** so the cycle is **~294 ps**. Signal routes **M0–M13**; the clock is an **H-tree on M14–M15**. Setup I talk to is **SSGNP, CworstCCworstT, 0.945 V, 125 °C**; hold is **FFGNP, CbestCCbestT, 1.05 V, 125 °C**. The sheet lists two voltages, **0.765 V and 0.80 V**, while those timing corners are **overdrive relative to 0.80 V** — so Fmax, Vmin, and physical rails are not the same sentence. The library is all **low-Vt: ELVT, ULVT, ULVTLL, LVT**. Closure is a **294 ps** problem: **H-tree latency/skew**, **tight M2 P34 pin access**, **cache/RF macros**, and **IR on the same corner we advertise 3.4 GHz**.

Add: *I owned [floorplan / CTS / STA / IR] …* when you have it.

---

## How to read this sheet (so you do not get trapped)

**1. 0.765 / 0.80 vs 0.945 / 1.05 / 0.75**  
Do **not** say “the CPU is a 0.945 V design.”  
- **0.765 V and 0.80 V** are the **multivoltage** line — likely **two rails or two operating points** (logic vs SRAM, or two AVS points). They are only **~35 mV** apart, so ask yourself: real UPF domains with LS, or two Fmax/Vmin points on one grid?  
- **0.945 V setup** and **1.05 V hold** are **overdrive / turbo-style** timing voltages on the functional mode.  
- **0.75 V typical power** sits next to the **0.765 V** rail — leakage/dynamic at a **low-V typical**, not at the 3.4 GHz corner.

One-liner: *3.4 GHz is an Fmax claim at high-V SS 0.945 V; power is quoted (when it exists) near 0.75 V TT; the chip still has 0.765/0.80 in the power intent.*

**2. Hold at 125 °C, not −40 °C**  
The sheet’s hold PVT is **FF, Cbest, 1.05 V, 125 °C**. Cold-min is often worse for hold. If asked: *This table shows one hold corner at 125 °C. I would still expect a cold hold in a real N3E deck; I would not tell a hiring panel that hold-at-hot is the only hold.*

**3. H-tree, not mesh**  
BK **specifies H-tree on M14–M15**. Do not say “we used a mesh” unless you later did. Thick top metals: **low RC, shielding, NDR, via stack from M15 down to sinks**.

**4. All low-Vt, power goal NA**  
No SVT/HVT on the sheet. **ELVT** is for the 294 ps cone; **ULVTLL / LVT** are the leakage knobs you still have. Power is **unbounded on this table** — interviewers will ask how you stopped ELVT from eating the rail.

**5. M2 P34**  
Tightest listed pitch. **Pin access, M2 coloring, via pillars, congestion** live here. Upper **P76 (M6–M11)** is where **long data and PG** want to go; **M14–M15** are **clock**.

**6. SHDMIM + UTRDL**  
**SHDMIM**: MIM decap in the stack — IR/dv/dt, not a DRC curiosity. **UTRDL**: thick RDL for **C4/bump / coarse PG** into 2.65 mm².

---

## Question bank

### Q1. Walk me through BK.

**A.** HPC CPU, **LAC RTL**, **N3E**, **2.65 mm²**, **H169PP54**, **3.4 GHz / 294 ps**. **15M** stack, route **M0–M13**, **H-tree M14–M15**. Setup **SS 0.945 V 125 °C CworstCCworstT**; hold **FF 1.05 V 125 °C CbestCCbestT**; power **TT 0.75 V 85 °C**. Vt **ELVT–LVT**. Rails **0.765 V and 0.80 V**. I close **period + H-tree + pin access + IR**, not a generic PPA loop.

### Q2. Why is this hard?

**A.** **294 ps** vs **~1.63 mm** span. H-tree insertion delay, via stack from M15, M2 P34 access, SI, LVF, and IR push-out are **percent-of-Fmax**, not rounding error. ELVT gets you delay and **leakage/IR**. Power goal NA means **nobody gave you a watt number to hide behind**.

### Q3. Timing budget on the whiteboard.

**A.**  
`294 ps ≥ Tcq + Tpd + Tsu + skew_eff + uncertainty + SI + IR_pushout + variation`  
Clock is an **H-tree on M14–M15**: latency is global, **local skew** at the leaf still kills bypass paths. I would not quote FO4 unless I measured it on LAC.

### Q4. Why H-tree on M14–M15? Why not a mesh?

**A.** Spec **chose H-tree** on the **two thickest metals**: low resistance, dedicated clock, shielding, predictable trunk. A mesh at 3.4 GHz is a **power/EM** tax. With **2.65 mm²**, a balanced H-tree can hit **skew** if trunks stay on M14–M15 and **taps/via farms** are planned. I still CTS for **local skew in EX/L1**, not only global H-tree skew. I would not claim mesh unless the flow added a leaf mesh.

### Q5. Decode the metal stack in 45 seconds.

**A.** **15 metals**: Xa–Xd / Ya–Yb / 4Y / 2Yy / 2Z + **UTRDL**. Pitches tighten at **M2 P34**, then open to **P76** from M6. **M0–M13** take signal; **M14–M15** are **H-tree**. **SHDMIM** is on-die decap. PG: **fine straps on mid layers, coarse on Y/Z/RDL**. I do not dump long data on M2.

### Q6. What does H169PP54 mean for you?

**A.** **169 nm-class** height and **54 nm** poly pitch: **track count, pin access, fin quantization, M1 P54 alignment**. Taller/HP cells help 3.4 GHz and **hurt density and leakage**. Floorplan util and **M2 congestion** must assume this cell, not a dense 7.5T-style library.

### Q7. Setup 0.945 V but multivoltage 0.765 / 0.80. Explain.

**A.** Different questions. **0.765 / 0.80** are **intent/rails or operating points**. **0.945 V SS max** is the **setup timing** voltage for the **3.4 GHz** functional corner — **overdrive vs 0.80 V**. I would map: which rail is the CPU logic, which is SRAM/array, whether LS sit on that 35 mV gap, and **whether 3.4 GHz is required at 0.80 V or only at 0.945 V**. Saying “Fmax at 0.765 V is 3.4 GHz” is almost certainly wrong.

### Q8. Hold corner: FF 1.05 V 125 °C. What is odd?

**A.** **High-V FF Cbest** is the right **RC and device** direction for hold. **125 °C** is **not** the usual cold hold. Device vs interconnect temp can go either way at N3E; I still ask CAD for **cold hold**. Hold at **1.05 V** with **ELVT** and **short LAC bypass** is the real risk. Scan hold is a second mode **not on this table**.

### Q9. CworstCCworstT vs CbestCCbestT?

**A.** **Cworst + CCworstT**: high interconnect RC + coupling in the **slow** direction — **setup**. **Cbest + CCbestT**: low RC, coupling in the **fast** direction — **hold**. At 3.4 GHz I close **both with SI**, not Cworst-only in PnR and surprise at signoff.

### Q10. Vt strategy with no SVT/HVT.

**A.** Palette is **ELVT / ULVT / ULVTLL / LVT** only. **ELVT** on the 294 ps cone; **ULVTLL/LVT** everywhere the path can afford. No HVT leakage floor. **Power NA** + **ELVT** + **0.945 V** is an **IR and leakage** problem. Wrong ELVT on a **min path** blows **hold at 1.05 V**.

### Q11. Two voltages 35 mV apart. Level shifters?

**A.** If they are **true simultaneous rails**, yes: **LS, isolation, UPF**, even at 35 mV (noise, IR, spec). If they are **two AVS / bin points** on one rail, **no LS**, but **libs, derate, and PG** still change. I would not invent LS count. I would ask for the **UPF**.

### Q12. Macros / L1 — still not on the edge by default.

**A.** **294 ps** does not pay for a **cache-port detour**. Pin side to the pipe, channel for **P34/M2 access**, macros on **PG + MIM**. Edge is for **cluster IO**, not a pretty SRAM ring. H-tree trunks on M14–M15 still need **vertical taps**; a macro wall **breaks tap/via farms**.

### Q13. IR on this stack.

**A.** CPU **di/dt** at 3.4 GHz. **UTRDL + Z/Yy** carry current; **SHDMIM** and filler decap hold the edge. Voltage drop at **0.945 V SS** is **delay** on the 294 ps path; drop at **0.765 V** is **function / SRAM**. I would not size PG only from the TT 0.75 V power corner.

### Q14. Congestion vs Fmax.

**A.** **M2 P34** hotspots at **RF/L1 ports** vs **H-tree blockage on M14–M15**. I will **move a macro or pad** before I detour an EX net onto extra vias. Overflow in a non-critical corner is cheaper than **20 ps** on LAC.

### Q15. Power corner TT 0.75 V 85 °C vs Fmax.

**A.** That corner is **typical energy/leakage**, not 3.4 GHz. Switching at **turbo 0.945–1.05 V** is a **different current**. Power goal **NA** means I still need a **current map for IR**, even without a watt target.

### Q16. What is missing from this sheet that you would still sign off?

**A.** Full **MCMM** (including **Vmin setup**, **cold hold**, **scan shift/capture**), **SI on/off**, **derate/LVF**, **SPEF vs extraction**, **IR/EM vectors**, **UPF**, **clock uncertainty vs H-tree spec**, **DFT**, **DRC/LVS**, **ECO/spares**. I would not tape out from three PVT bullets.

### Q17. Behavioral: what would you not do?

**A.** Template: *I would not treat 0.945 V setup as the only voltage in the design. I would not CTS an H-tree on M14–M15 without a via/tap plan through the 15M stack. I would not flood ELVT because power is NA. I would not waive LAC paths I cannot defend.*

---

## Whiteboard drills

1. **294 ps** setup at **0.945 V SS Cworst** and hold at **1.05 V FF Cbest**, with H-tree launch/capture on **M14–M15**.  
2. Layer map: **M2 P34** pins, **M6–M11 P76** data/PG, **M14–M15** H-tree, **UTRDL** bumps.  
3. Two boxes: **rails 0.765/0.80** vs **timing 0.945/1.05** vs **power 0.75**.  
4. Macro + H-tree tap: why an edge SRAM ring **breaks clock vias and cache timing**.

---

## Trap list

- **N3E is GAA** — false; FinFET.  
- **3.4 GHz at 0.765 V** — not what the setup corner says.  
- **Mesh** — sheet says **H-tree M14–M15**.  
- **SVT/HVT leakage recovery** — not on the Vt list.  
- **Hold only needs this 125 °C corner** — incomplete.  
- **2.65 mm² is the SoC** — core-class.  
- **Power NA means IR does not matter.**  
- Invented WNS/TNS, util, or UPF.

## Still needed from you

Role/ownership, instance count, util, SRAM/RF map, UPF (are 0.765/0.80 two rails?), full MCMM, derate, WNS/TNS, IR, DFT, ECO, what you closed.
