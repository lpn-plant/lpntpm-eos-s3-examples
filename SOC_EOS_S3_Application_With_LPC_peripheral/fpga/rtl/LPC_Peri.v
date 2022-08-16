`timescale 1 ns / 1 ps

module LPC_Peri (

   input  wire        lpc_lclk         , // LPC external clock 33Mhz
   input  wire        lpc_lreset_n     , // Reset - Active Low 
   input  wire        lpc_lframe_n     , // Frame - Active Low
   inout  wire [ 3:0] lpc_lad_in       , //4-bit LAD bi-directional and tri-state bus
   input  wire        i_addr_hit     ,
   output reg  [ 4:0] o_current_state,
   input  wire [ 7:0] i_din          ,
   output reg  [ 7:0] o_lpc_data_in  ,
   output wire [ 3:0] o_lpc_data_out ,
   output wire [15:0] o_lpc_addr     ,
   output wire        o_lpc_en       ,
   output wire        o_io_rden_sm   ,
   output wire        o_io_wren_sm   ,
   output reg  [31:0] TDATA        ,
   output reg         READY               
);

//---- internal signals -----------------------
  reg           sync_en;
  reg  [3:0] rd_addr_en;
  wire [1:0] wr_data_en;
  wire [1:0] rd_data_en;
  reg             tar_F;
  reg  [15:0] o_lpc_addr_reg;
 
  reg  [4:0] fsm_next_state;
  reg  [4:0] previous_state;
   
  wire [31:0] vec1 = 32'b00000000000000000000000000000000;
  reg [12:0] licznik = 13'b0000000000000;
  reg [12:0] cnt2 = 13'b0000000000000;
  reg [12:0] cnt3 = 13'b0000000000000;
  reg [12:0] cnt4 = 13'b0000000000000;
  reg [1:0] cycle_type = 2'b00; //"00" none, "01" write, "11" read
  integer cycle_cnt = 0;
  reg sendPackage;
  reg saveCycle;
  reg [15:0] lpc_addrBuf = 16'b0000000000000000;
  reg [7:0] lpc_data_inBuf  = 8'b00000000;
  reg [31:0] dinAbuf = 32'b00000000000000000000000000000000;
  wire [31:0] doutBbuf = 32'b00000000000000000000000000000000;
  integer address_cnt = 1'b0;
  reg in_service = 1'b0;
  
  reg [31:0] memoryLPC [0:2]; //memory array 2x32bit
  reg readyWasHigh = 1'b0;
  reg wasLframeLow = 1'b0;
  reg wasLpc_enHigh = 1'b0;
  reg newValuedata = 1'b0;
  
  assign o_lpc_addr = o_lpc_addr_reg;
  
  //---- FSM states definitions --------------------------
   `define LPC_IDLE_STATE             5'h00   //LPC Idle state
   `define LPC_START_STATE            5'h01   //LPC Start state  //was: 5'h01
   `define LPC_IO_RD_STATE            5'h02   // Read cycle
   `define LPC_IO_RD_ADDR_CLK1_STATE  5'h03   // LPC Address state (1cycle)  RD
   `define LPC_IO_RD_ADDR_CLK2_STATE  5'h04   // LPC Address state (2 cycle) RD
   `define LPC_IO_RD_ADDR_CLK3_STATE  5'h05   // LPC Address state (3 cycle) RD
   `define LPC_IO_RD_ADDR_CLK4_STATE  5'h06   // LPC Address state (4 cycle) RD
   `define LPC_IO_RD_TAR_CLK1_STATE   5'h07   // LPC Host Turnaround 1 (Drive LAD 4'hF)
   `define LPC_IO_RD_TAR_CLK2_STATE   5'h08   // LPC Host Turnaround 2 (Float LAD)
   `define LPC_IO_RD_SYNC_STATE       5'h09   // LPC Sync State (may be multiple cycles for wait-states)
   `define LPC_IO_RD_DATA_CLK1_STATE  5'h0B   // LPC Host Data state (1 cycle)
   `define LPC_IO_RD_DATA_CLK2_STATE  5'h0C   // LPC Host Data state (2 cycle)
   `define LPC_IO_WR_STATE            5'h0D   // Write cycle
   `define LPC_IO_WR_ADDR_CLK1_STATE  5'h0E   // LPC Address state (1cycle) WR
   `define LPC_IO_WR_ADDR_CLK2_STATE  5'h0F   // LPC Address state (1cycle) WR
   `define LPC_IO_WR_ADDR_CLK3_STATE  5'h10   // LPC Address state (1cycle) WR
   `define LPC_IO_WR_ADDR_CLK4_STATE  5'h11   // LPC Address state (1cycle) WR
   `define LPC_IO_WR_DATA_CLK1_STATE  5'h12   // LPC Host Data state (1 cycle) WR
   `define LPC_IO_WR_DATA_CLK2_STATE  5'h13   // LPC Host Data state (2 cycle) WR
   `define LPC_IO_WR_TAR_CLK1_STATE   5'h14   // LPC Host Turnaround 1 
   `define LPC_IO_WR_TAR_CLK2_STATE   5'h15   // LPC Host Turnaround 2
   `define LPC_IO_WR_SYNC_STATE       5'h16   // LPC Sync State (may be multiple cycles for wait-states)
   `define LPC_LALPC_TAR_CLK1_STATE   5'h18   // LPC Host Turnaround 1 
   `define LPC_LALPC_TAR_CLK2_STATE   5'h19   // LPC Host Turnaround 2 
   
   
always @ (posedge lpc_lclk) begin    //save cycle type
   if (~lpc_lreset_n) cycle_type <= 2'b00;
   else if (lpc_lclk) begin
     cycle_type <= 2'b00;
     if (o_io_rden_sm) begin
       cycle_type <= 2'b11; //read
     end;
     if (o_io_wren_sm) begin
      cycle_type <= 2'b01; //write
     end;
   end;
end

always @ (posedge lpc_lclk) begin  //saving LPC protocol data 2 out databus
  if (lpc_lframe_n==1'b0)
  begin
    wasLframeLow = 1'b1;
    cycle_cnt = 0;
    wasLpc_enHigh = 1'b0;
  end
   if ((o_lpc_en) && (wasLframeLow))
   begin
    wasLpc_enHigh = 1'b1;
   end 
   if (wasLpc_enHigh)
   begin
    cycle_cnt = cycle_cnt + 1;
    if ((cycle_cnt > 1) && (cycle_cnt < 3))
    begin
        dinAbuf[31:28] <= 4'b0000;
        dinAbuf[27:12] <= o_lpc_addr_reg;
        dinAbuf[11:4] <= o_lpc_data_in;
        dinAbuf[3:2] <= 2'b00;
        dinAbuf[1:0] <= cycle_type;
        if (dinAbuf==memoryLPC[0]) newValuedata = 1'b0;
        else newValuedata = 1'b1;      
        TDATA <= dinAbuf;  
        memoryLPC[0] <= dinAbuf;       
    end
    else if ( (cycle_cnt >=3) && (cycle_cnt < 5))
    begin
      if (newValuedata) READY <= 1'b1;
      else READY <= 1'b0;
    end
    else if  (cycle_cnt >= 5)
    begin
      READY <= 1'b0;
      wasLpc_enHigh = 1'b0;
      wasLframeLow = 1'b0;
      cycle_cnt = 0;
    end
  end      
end 

always @ (posedge lpc_lclk or negedge lpc_lreset_n) begin
   if (~lpc_lreset_n) o_current_state <= `LPC_IDLE_STATE;
   else 
   begin
     previous_state <= o_current_state;
     o_current_state <= fsm_next_state;
   end
end

//FSM - version for I/O cycles
always @(*)
begin
  if (lpc_lreset_n == 1'b0) fsm_next_state <= `LPC_IDLE_STATE;
  if (lpc_lframe_n == 1'b0) fsm_next_state <= `LPC_IDLE_STATE; 
     case(o_current_state)
       `LPC_IDLE_STATE:
        begin
          if (lpc_lreset_n == 1'b0) fsm_next_state <= `LPC_IDLE_STATE;
          else if ((lpc_lframe_n == 1'b0) && (lpc_lad_in == 4'h0)) fsm_next_state <= `LPC_START_STATE;
        end
        `LPC_START_STATE:
         begin
           if ((lpc_lframe_n == 1'b0) && (lpc_lad_in == 4'h0)) fsm_next_state <= `LPC_START_STATE;  
           else if ((lpc_lframe_n == 1'b1) && (lpc_lad_in == 4'h0)) fsm_next_state <= `LPC_IO_RD_STATE;   
           else if ((lpc_lframe_n == 1'b1) && (lpc_lad_in == 4'h2)) fsm_next_state <= `LPC_IO_WR_STATE;        
         end 
         `LPC_IO_RD_STATE: 
          fsm_next_state <= `LPC_IO_RD_ADDR_CLK1_STATE;
         `LPC_IO_RD_ADDR_CLK1_STATE:
          fsm_next_state <= `LPC_IO_RD_ADDR_CLK2_STATE;
         `LPC_IO_RD_ADDR_CLK2_STATE:
          fsm_next_state <= `LPC_IO_RD_ADDR_CLK3_STATE;
         `LPC_IO_RD_ADDR_CLK3_STATE:
          fsm_next_state <= `LPC_IO_RD_ADDR_CLK4_STATE;
         `LPC_IO_RD_ADDR_CLK4_STATE:
          fsm_next_state <= `LPC_IO_RD_TAR_CLK1_STATE;
         `LPC_IO_RD_TAR_CLK1_STATE:
          fsm_next_state = `LPC_IO_RD_TAR_CLK2_STATE;
         `LPC_IO_RD_TAR_CLK2_STATE:
          begin
            if (i_addr_hit == 1'b0) fsm_next_state = `LPC_IDLE_STATE;
            if (i_addr_hit == 1'b1) fsm_next_state = `LPC_IO_RD_SYNC_STATE;
          end
         `LPC_IO_RD_SYNC_STATE:
          fsm_next_state <= `LPC_IO_RD_DATA_CLK1_STATE;
         `LPC_IO_RD_DATA_CLK1_STATE:
          fsm_next_state <= `LPC_IO_RD_DATA_CLK2_STATE;
         `LPC_IO_RD_DATA_CLK2_STATE:
          fsm_next_state <= `LPC_LALPC_TAR_CLK1_STATE;
         `LPC_IO_WR_STATE:
          fsm_next_state <= `LPC_IO_WR_ADDR_CLK1_STATE; 
         `LPC_IO_WR_ADDR_CLK1_STATE:
          fsm_next_state <= `LPC_IO_WR_ADDR_CLK2_STATE; 
         `LPC_IO_WR_ADDR_CLK2_STATE:
          fsm_next_state <= `LPC_IO_WR_ADDR_CLK3_STATE;
         `LPC_IO_WR_ADDR_CLK3_STATE:
          fsm_next_state <= `LPC_IO_WR_ADDR_CLK4_STATE;
         `LPC_IO_WR_ADDR_CLK4_STATE:
          fsm_next_state <= `LPC_IO_WR_DATA_CLK1_STATE; 
         `LPC_IO_WR_DATA_CLK1_STATE:
          fsm_next_state <= `LPC_IO_WR_DATA_CLK2_STATE; 
         `LPC_IO_WR_DATA_CLK2_STATE:
          fsm_next_state <= `LPC_IO_WR_TAR_CLK1_STATE;
         `LPC_IO_WR_TAR_CLK1_STATE:
          fsm_next_state <= `LPC_IO_WR_TAR_CLK2_STATE;
         `LPC_IO_WR_TAR_CLK2_STATE:
          begin
            if (i_addr_hit == 1'b0) fsm_next_state <= `LPC_IDLE_STATE;
            if (i_addr_hit == 1'b1) fsm_next_state <= `LPC_IO_WR_SYNC_STATE;
          end
         `LPC_IO_WR_SYNC_STATE:
          fsm_next_state <= `LPC_LALPC_TAR_CLK1_STATE;  
         `LPC_LALPC_TAR_CLK1_STATE:
          fsm_next_state <= `LPC_LALPC_TAR_CLK2_STATE;
         default: 
         begin
           if (lpc_lreset_n == 1'b0) fsm_next_state <= `LPC_IDLE_STATE;
           if (lpc_lframe_n == 1'b0) fsm_next_state <= `LPC_IDLE_STATE; 
           fsm_next_state <= `LPC_IDLE_STATE; 
         end            
    endcase
     
end                                

assign rd_data_en = (fsm_next_state == `LPC_IO_RD_DATA_CLK1_STATE) ? 2'b01 :
                    (fsm_next_state == `LPC_IO_RD_DATA_CLK2_STATE) ? 2'b10 :
                    2'b00;
                    
assign o_lpc_data_out = (sync_en == 1'b1      ) ? 4'h0     :
                      (tar_F == 1'b1        ) ? 4'hF     :
                      (lpc_lframe_n == 1'b0     ) ? 4'h0     :  
                      (rd_data_en[0] == 1'b1) ? i_din[3:0] :
                      (rd_data_en[1] == 1'b1) ? i_din[7:4] :
                      4'h0;

assign lpc_lad_in = (o_current_state == `LPC_IO_WR_SYNC_STATE) ? 4'b0000 : 4'bzzzz;
assign lpc_lad_in = (rd_data_en[0]) ? o_lpc_data_out: 4'bzzzz;
assign lpc_lad_in = (rd_data_en[1]) ? o_lpc_data_out: 4'bzzzz;     

assign  o_io_wren_sm = (fsm_next_state == `LPC_IO_WR_TAR_CLK1_STATE) ? 1'b1 :
                    (fsm_next_state == `LPC_IO_WR_TAR_CLK2_STATE) ? 1'b1 :
                    1'b0;

always @ (posedge lpc_lclk) begin
   if (wr_data_en[0]) o_lpc_data_in[3:0] <= lpc_lad_in;
   if (wr_data_en[1]) o_lpc_data_in[7:4] <= lpc_lad_in;
end    

assign o_lpc_en = (sync_en == 1'b1      ) ? 1'h1 :
                (tar_F == 1'b1        ) ? 1'h1 :
                (lpc_lframe_n == 1'b0     ) ? 1'h0 :  
                (rd_data_en[0] == 1'b1) ? 1'b1 :
                (rd_data_en[1] == 1'b1) ? 1'b1 :
                1'h0;                

always @(*)
begin
   tar_F <= 1'b0;
  case(fsm_next_state)
   `LPC_IO_RD_SYNC_STATE:
    sync_en <= 1'b1;
   `LPC_IO_WR_SYNC_STATE:
    sync_en <= 1'b1;
   `LPC_LALPC_TAR_CLK1_STATE:
    tar_F <= 1'b1;
   `LPC_IO_RD_ADDR_CLK1_STATE:
    rd_addr_en <= 4'b1000;
   `LPC_IO_RD_ADDR_CLK2_STATE:
    rd_addr_en <= 4'b0100; 
   `LPC_IO_RD_ADDR_CLK3_STATE:
    rd_addr_en <= 4'b0010; 
   `LPC_IO_RD_ADDR_CLK4_STATE:
    rd_addr_en <= 4'b0001;  
   `LPC_IO_WR_ADDR_CLK1_STATE:
    rd_addr_en <= 4'b1000;
   `LPC_IO_WR_ADDR_CLK2_STATE:
    rd_addr_en <= 4'b0100;                  
   `LPC_IO_WR_ADDR_CLK3_STATE:
    rd_addr_en <= 4'b0010; 
   `LPC_IO_WR_ADDR_CLK4_STATE:
    rd_addr_en <= 4'b0001;                                             
   default:
   begin
    rd_addr_en <= 4'b0000;
    tar_F <= 1'b0;
    sync_en <= 1'b0;
   end                
  endcase  
end                                     

assign o_io_rden_sm = (fsm_next_state == `LPC_IO_RD_TAR_CLK1_STATE) ? 1'b1 :
                    (fsm_next_state == `LPC_IO_RD_TAR_CLK2_STATE) ? 1'b1 :
                    1'b0;
                    
assign wr_data_en = (fsm_next_state == `LPC_IO_WR_DATA_CLK1_STATE) ? 2'b01 :
                    (fsm_next_state == `LPC_IO_WR_DATA_CLK2_STATE) ? 2'b10 :
                    2'b00;                      


always @ (posedge lpc_lclk)
begin
  if (rd_addr_en[3] == 1'b1) o_lpc_addr_reg[15:12] = lpc_lad_in;
  else if (rd_addr_en[3] == 1'b10) o_lpc_addr_reg[15:12] = o_lpc_addr_reg[15:12]; 
  if (rd_addr_en[2] == 1'b1) o_lpc_addr_reg[11:8] = lpc_lad_in;
  else if (rd_addr_en[2] == 1'b10) o_lpc_addr_reg[11:8] = o_lpc_addr_reg[11:8];
  if (rd_addr_en[1] == 1'b1) o_lpc_addr_reg[7:4] = lpc_lad_in;
  else if (rd_addr_en[1] == 1'b10) o_lpc_addr_reg[7:4] = o_lpc_addr_reg[7:4];
  if (rd_addr_en[0] == 1'b1) o_lpc_addr_reg[3:0] = lpc_lad_in;
  else if (rd_addr_en[0] == 1'b10) o_lpc_addr_reg[3:0] = o_lpc_addr_reg[3:0];
end

endmodule

