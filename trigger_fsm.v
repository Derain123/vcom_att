
module trigger_fsm (
  input clk,
  input [39:0] ex_reg_pc
  );

always@(posedge clk) begin
  if(ex_reg_pc==40'h8000_0000) begin
    $trigger;
  end
end

endmodule
