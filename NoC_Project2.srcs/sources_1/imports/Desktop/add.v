`timescale 1ns/1ps

module add #(parameter id_width = 'd3, x_size = 1, y_size = 1, data_width = 32, total_width = id_width + data_width + x_size + y_size)
(
    input clk,
    input rstn,
    input r_valid_pe,
    input [total_width-1:0] r_data_pe,
    output r_ready_pe,
    output reg w_valid_pe,
    input w_ready_pe,
    output reg [total_width-1:0] w_data_pe
);

wire [x_size+y_size-1:0] xy_size = 0;
wire [(data_width/2)-1:0] tp = 0;

assign r_ready_pe = (w_valid_pe) ? w_ready_pe : 1'b1;

always @(posedge clk) begin
    if (!rstn) begin
        w_valid_pe <= 1'b0;
    end else begin
            if (r_valid_pe) begin 
            w_data_pe <= {r_data_pe[total_width-1:total_width-id_width],tp,(r_data_pe[total_width-id_width-1:total_width-id_width-(data_width/2)] + r_data_pe[total_width-id_width-(data_width/2)-1:total_width-id_width-data_width]), xy_size};
            w_valid_pe <= 1'b1;
            end else if (r_ready_pe&w_valid_pe) w_valid_pe <= 1'b0;
        end
end

endmodule
