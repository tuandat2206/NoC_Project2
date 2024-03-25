`timescale 1ns/1ps

`define X 2
`define Y 2
`define id 3
`define data_width 32
`define pkt_no_field_size 0
//`define clkPeriod 20  // cycle
`define x_size $clog2(`X)
`define y_size $clog2(`Y)
`define total_width (`x_size+`y_size+`id+`pkt_no_field_size+`data_width)

class packet_send;
  logic [2:0] id;
  rand logic [15:0] data_a;
  rand logic [15:0] data_b;
  rand logic x_coor;
  rand logic y_coor;
  logic [31:0] result_exp;
  logic [36:0] data;
  
  constraint data_c {
    data_a >= data_b;
    data_a <= 20000;
    data_b <= 20000;
  }
  
  task concat();
      data = {id, data_a, data_b, y_coor, x_coor};
  endtask
  
  task expect_res();
    result_exp = ({x_coor, y_coor} == 2'b00) ? {data_a, data_b} : 
    ({x_coor, y_coor} == 2'b01) ? {data_a, data_b} >> 1 : 
    ({x_coor, y_coor} == 2'b10) ? data_a + data_b : 
    ({x_coor, y_coor} == 2'b11) ? data_a - data_b : 36'bx;
  endtask
  
  function void display();
    $write("At %0t - [PACKET SEND]: ", $time);
    case({x_coor, y_coor}) 
      2'b00: begin
        $display("OP: XXX \tID = %d \tDATA = %d \tEXP = %d", id, {data_a, data_b}, {data_a, data_b});
      end
      2'b01: begin
        $display("OP: >> 1 \tID = %d \tDATA = %d \tEXP = %d", id, {data_a, data_b}, {data_a, data_b} >> 1);
      end
      2'b10: begin
        $display("OP: + \tID = %d \tDATA_A = %d \tDATA_B = %d \tEXP = %d", id, data_a, data_b, data_a + data_b);
      end
      2'b11: begin
        $display("OP: - \tID = %d \tDATA_A = %d \tDATA_B = %d \tEXP = %d", id, data_a, data_b, data_a - data_b);
      end
      default:
        $display("This packet wasn't randomized before");
    endcase
  endfunction

  function packet_send copy();
    copy = new();
    copy.x_coor = this.x_coor;
    copy.y_coor = this.y_coor;
    copy.data_a = this.data_a;
    copy.data_b = this.data_b;
    copy.id = this.id;
    copy.result_exp = this.result_exp;
    copy.data = this.data;
  endfunction
endclass

class packet_receive;
  logic [36:0] data;
  logic id;
  logic [31:0] result;
  logic y_dest;
  logic x_dest;

  function void display();
    $write("\nAt %0t - [PACKET RECEIVE]: ID = %0d, RESULT = %0d", $time, this.id, this.result);
  endfunction
  
  task seperate();
    id = data[36:34];
    result = data[33:2];
    y_dest = data[1];
    x_dest = data[0];
  endtask  
endclass

module tb;  
  
  reg clk;
  reg rstn;
  reg r_valid_pe_io;
  reg [`total_width-1:0] r_data_pe_io;
  wire r_ready_pe_io;
  reg w_ready_pe_io;
  wire [`total_width-1:0] w_data_pe_io;
  wire w_valid_pe_io;
  
  openNocTop #(.X(`X),.Y(`Y),.id_width(`id),.data(`data_width),.pkt_no_field_size(`pkt_no_field_size)) DUT
  (
    .clk(clk),
    .rstn(rstn),
    .r_valid_pe_io(r_valid_pe_io),
    .r_data_pe_io(r_data_pe_io),
    .r_ready_pe_io(r_ready_pe_io),
    .w_valid_pe_io(w_valid_pe_io),
    .w_data_pe_io(w_data_pe_io),
    .w_ready_pe_io(w_ready_pe_io)
  );

  packet_send test_pkt[7];
  packet_send pkt_snd;
  packet_receive pkt_rcv;
  
  bit rw_random;
  bit flag_id[7] = {0, 0, 0, 0, 0, 0, 0};
  bit take_id = 1'b0;
  
  logic [2:0] id_pkt;
  
  int clk_cycle = 10;
  int op_count;
  int op_write = 0;
  int op_read = 0;
  int op_pass= 0;
  int op_fail = 0;
  
  reg [2:0] id_cmp;
  reg done_all_write = 1'b0;
  reg done_all_read = 1'b0;
  
  event done;
  
  task compare(input packet_send pkt_send, input packet_receive pkt_rcv);
      if (pkt_send.result_exp == pkt_rcv.result) begin
        $display(" vs EXPECT = %d --> PASS", pkt_send.result_exp);
        op_pass++;
      end
      else begin
        $display(" vs EXPECT = %d --> FAIL", pkt_send.result_exp);
        op_fail++;
      end
  endtask
  
  task read();
    if (w_valid_pe_io == 1'b1) begin
      pkt_rcv = new();
      pkt_rcv.data = w_data_pe_io;
      id_cmp = w_data_pe_io[36:34];
      if (flag_id[id_cmp] == 1'b1) begin
        pkt_rcv.seperate(); 
        pkt_rcv.display();
        compare(test_pkt[id_cmp], pkt_rcv);
        flag_id[id_cmp] = 1'b0;
        op_read++;
      end else begin
        $display("\nThis received-packet may be written before");
      end
    end else $display("\nDon't have any packet to be sent back");
  endtask

  task write();
    if (r_ready_pe_io == 1'b1 && op_write < op_count) begin
      take_id = 1'b0;
      r_valid_pe_io = 1'b0;
      for (id_pkt = 0; id_pkt < 7; id_pkt = id_pkt + 3'b001) begin
        if (flag_id[id_pkt] == 1'b0) begin
          pkt_snd = new();
          pkt_snd.id = id_pkt;
          pkt_snd.randomize();
          pkt_snd.concat();
          pkt_snd.expect_res();
          r_valid_pe_io = 1'b1;
          r_data_pe_io = pkt_snd.data;
          test_pkt[id_pkt] = pkt_snd.copy();
          flag_id[id_pkt] = 1'b1;
          pkt_snd.display();
          take_id = 1'b1;
          op_write++;
          break;
        end
      end
      if (take_id == 1'b0) $display("Cannot create packet because all ID had been taken");
      end else $display("Not ready to send packet");
  endtask
  

  always #(clk_cycle/2) clk = ~clk;  
  initial begin
    op_count = 251;
    clk = 1'b0;
    rstn = 1'b0;
    r_valid_pe_io = 1'b0;
    r_data_pe_io = 37'b0;
    w_ready_pe_io = 1'b0;
    #(clk_cycle) 
    rstn = 1'b1;
    #(5*clk_cycle) 
    w_ready_pe_io = 1'b1;
    rw_random = 1'b1;
    wait (done.triggered);
    $display("=================== DONE SIMULATION ===================");
    $display("Number of Packet: \t\t\t%d", op_count);
    $display("Number of Packet PASS: \t%d", op_pass);
    $display("Number of Packet FAIL: \t%d", op_fail);
    $display("Accuracy: \t\t\t\t\t\t\t%d", op_pass*100/op_count);
    #(clk_cycle) $finish;
  end
  
  always @(op_write or op_read) begin
    if (op_write == op_count && op_read == op_count) -> done;
  end
  
  always @(posedge clk) begin
    if (rw_random) begin
      #1 read();
      write();
    end
  end
endmodule

//    r_data_pe_io = 37'b000_0000000000001111_0000000000001111_0_1;     //15 + 15 = 30
//    #(clk_cycle) 
//    r_data_pe_io = 37'b001_0000111100001111_0000000000001111_1_1;
//    #(clk_cycle)
//    r_data_pe_io = 37'b011_0000000000000000_0000000000100000_0_0;
//    #(clk_cycle)
//    r_data_pe_io = 37'b010_0000000000000000_0000000100000000_1_0;