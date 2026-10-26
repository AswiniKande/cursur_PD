// practice_core — small hierarchical netlist for fc_shell practice.
// Bit-blasted ports (din_0 .. din_7) keep the Tcl queries easy to read.
// Data path is intentionally toy-sized: a registered file, a 4-bit alu, a decoder, and a controller.

module regbit (clk, rst_n, d, en, q);
  input clk, rst_n, d, en;
  output q;
  wire d_g, qn;
  MUX2 u_mx (.A(q), .B(d), .S(en), .Y(d_g));
  DFFR u_ff (.D(d_g), .CK(clk), .RSTN(rst_n), .Q(q), .QN(qn));
endmodule

module alu4 (clk, a0, a1, a2, a3, b0, b1, b2, b3, op, y0, y1, y2, y3);
  input clk, a0, a1, a2, a3, b0, b1, b2, b3, op;
  output y0, y1, y2, y3;
  wire n0, n1, n2, n3, m0, m1, m2, m3, p0, p1, p2, p3, qn0, qn1, qn2, qn3;
  NAND2 u_n0 (.A(a0), .B(b0), .Y(n0));
  NAND2 u_n1 (.A(a1), .B(b1), .Y(n1));
  NAND2 u_n2 (.A(a2), .B(b2), .Y(n2));
  NAND2 u_n3 (.A(a3), .B(b3), .Y(n3));
  NOR2 u_r0 (.A(a0), .B(b0), .Y(m0));
  NOR2 u_r1 (.A(a1), .B(b1), .Y(m1));
  NOR2 u_r2 (.A(a2), .B(b2), .Y(m2));
  NOR2 u_r3 (.A(a3), .B(b3), .Y(m3));
  MUX2 u_m0 (.A(n0), .B(m0), .S(op), .Y(p0));
  MUX2 u_m1 (.A(n1), .B(m1), .S(op), .Y(p1));
  MUX2 u_m2 (.A(n2), .B(m2), .S(op), .Y(p2));
  MUX2 u_m3 (.A(n3), .B(m3), .S(op), .Y(p3));
  DFF u_q0 (.D(p0), .CK(clk), .Q(y0), .QN(qn0));
  DFF u_q1 (.D(p1), .CK(clk), .Q(y1), .QN(qn1));
  DFF u_q2 (.D(p2), .CK(clk), .Q(y2), .QN(qn2));
  DFF u_q3 (.D(p3), .CK(clk), .Q(y3), .QN(qn3));
endmodule

module decoder (clk, valid_in, d0, d1, en_alu, en_rf, valid_q);
  input clk, valid_in, d0, d1;
  output en_alu, en_rf, valid_q;
  wire n0, n1, n2, vqn;
  INV u_i0 (.A(d0), .Y(n0));
  NAND2 u_a0 (.A(valid_in), .B(n0), .Y(n1));
  NAND2 u_a1 (.A(valid_in), .B(d1), .Y(n2));
  INV u_i1 (.A(n1), .Y(en_alu));
  INV u_i2 (.A(n2), .Y(en_rf));
  DFF u_vq (.D(valid_in), .CK(clk), .Q(valid_q), .QN(vqn));
endmodule

module control (clk, rst_n, valid_in, start, run);
  input clk, rst_n, valid_in;
  output start, run;
  wire s0, s1, n0, n1, qn0, qn1;
  DFFR u_s0 (.D(valid_in), .CK(clk), .RSTN(rst_n), .Q(s0), .QN(qn0));
  DFFR u_s1 (.D(s0), .CK(clk), .RSTN(rst_n), .Q(s1), .QN(qn1));
  AND2 u_a0 (.A(s0), .B(valid_in), .Y(n0));
  BUF u_b0 (.A(n0), .Y(start));
  OR2 u_o0 (.A(s0), .B(s1), .Y(n1));
  CLKBUF u_c0 (.A(n1), .Y(run));
endmodule

module practice_core (clk, rst_n, din_0, din_1, din_2, din_3, din_4, din_5, din_6, din_7, valid_in, dout_0, dout_1, dout_2, dout_3, dout_4, dout_5, dout_6, dout_7, valid_out);
  input clk, rst_n, din_0, din_1, din_2, din_3, din_4, din_5, din_6, din_7, valid_in;
  output dout_0, dout_1, dout_2, dout_3, dout_4, dout_5, dout_6, dout_7, valid_out;
  wire clk_i, rst_i, run, start, en_alu, en_rf, valid_q;
  wire rf0, rf1, rf2, rf3, rf4, rf5, rf6, rf7;

  CLKBUF u_clkbuf (.A(clk), .Y(clk_i));
  BUF u_rstbuf (.A(rst_n), .Y(rst_i));

  regbit u_rf0 (.clk(clk_i), .rst_n(rst_i), .d(din_0), .en(run), .q(rf0));
  regbit u_rf1 (.clk(clk_i), .rst_n(rst_i), .d(din_1), .en(run), .q(rf1));
  regbit u_rf2 (.clk(clk_i), .rst_n(rst_i), .d(din_2), .en(run), .q(rf2));
  regbit u_rf3 (.clk(clk_i), .rst_n(rst_i), .d(din_3), .en(run), .q(rf3));
  regbit u_rf4 (.clk(clk_i), .rst_n(rst_i), .d(din_4), .en(run), .q(rf4));
  regbit u_rf5 (.clk(clk_i), .rst_n(rst_i), .d(din_5), .en(run), .q(rf5));
  regbit u_rf6 (.clk(clk_i), .rst_n(rst_i), .d(din_6), .en(run), .q(rf6));
  regbit u_rf7 (.clk(clk_i), .rst_n(rst_i), .d(din_7), .en(run), .q(rf7));

  decoder u_dec (.clk(clk_i), .valid_in(valid_in), .d0(din_0), .d1(din_1), .en_alu(en_alu), .en_rf(en_rf), .valid_q(valid_q));
  control u_ctrl (.clk(clk_i), .rst_n(rst_i), .valid_in(valid_in), .start(start), .run(run));
  alu4 u_alu (.clk(clk_i), .a0(rf0), .a1(rf1), .a2(rf2), .a3(rf3), .b0(rf4), .b1(rf5), .b2(rf6), .b3(rf7), .op(en_alu), .y0(dout_0), .y1(dout_1), .y2(dout_2), .y3(dout_3));

  BUF u_d4 (.A(rf4), .Y(dout_4));
  BUF u_d5 (.A(rf5), .Y(dout_5));
  BUF u_d6 (.A(rf6), .Y(dout_6));
  BUF u_d7 (.A(rf7), .Y(dout_7));
  BUF u_vout (.A(valid_q), .Y(valid_out));
endmodule
