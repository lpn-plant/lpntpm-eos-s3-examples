
`timescale 1ns / 10ps

// each BREATHE output will have its own register for settings.
// BREATHE_x_CONFIG
//      BREATHE_x_CLK_CYCLES_PER_STEP       - [23:0]    (how many clk cycles per brightness step)
//      BREATHE_x_RESERVED                  - [30:24]   future-use (number of breaths to take...)
//      BREATHE_x_EN                        - [31]      1 to enable, 0 to disable
// so, for each IO, we will have 1 register BREATHE_x_CONFIG (addr = 0,4,8...)

module AL4S3B_FPGA_ONION_LPCCTRL ( 
    
    // AHB-To_FPGA Bridge I/F
    WBs_ADR_i,
    WBs_CYC_i,
    WBs_BYTE_STB_i,
    WBs_WE_i,
    WBs_STB_i,
    WBs_DAT_i,
    WBs_CLK_i,  //80 MHz
    WBs_RST_i,
    WBs_DAT_o,
    WBs_ACK_o,

    // System clk 33 Mhz
    Sys_clk,
	
	//System reset
	Sys_reset,
            
    // BREATHE signals
    BREATHE_o,
      
    // TIMER signals
    TIMER_o,
	
	// LPC Slave Interface
	lpc_lclk,     // LPC clock 33 Mhz
	lpc_lreset_n, // Reset - Active Low 
	lpc_lframe_n, // LPC Frame - Active Low
	lpc_lad_in    // Bi-directional 4-bit LAD bus (tri-state)	
);


// MODULE Parameters =====================================================================

// This is the value that is returned when a non-implemented register is read.
parameter   DEFAULT_REG_VALUE                       = 32'hDEF_FAB_AC;   // no such register

parameter   BREATHE_PWM_RESOLUTION_BITS             = 8;                // future-use

parameter   DEFAULT_BREATHE_CLK_CYCLES_PER_STEP     = 24'hAAAA;         // 1-sec-inhale,1-sec-exhale


// MODULE Internal Parameters ============================================================
// Allow for up to 256 registers in this module
localparam  ADDRWIDTH                   =  10;

// register offsets.
localparam  REG_ADDR_BREATHE_0_CONFIG   =  10'h000        ;
localparam  REG_ADDR_BREATHE_1_CONFIG   =  10'h004        ;
localparam  REG_ADDR_BREATHE_2_CONFIG   =  10'h008        ;
localparam  REG_ADDR_TIMER_0_CONFIG     =  10'h00C        ; //new value


// MODULE PORT Declarations and Data Types ===============================================

// AHB-To_FPGA Bridge I/F
input       wire    [16:0]      WBs_ADR_i           ;  // Address Bus                   to   FPGA
input       wire                WBs_CYC_i           ;  // Cycle Chip Select             to   FPGA 
input       wire    [3:0]       WBs_BYTE_STB_i      ;  // Byte Select                   to   FPGA
input       wire                WBs_WE_i            ;  // Write Enable                  to   FPGA
input       wire                WBs_STB_i           ;  // Strobe Signal                 to   FPGA
input       wire    [31:0]      WBs_DAT_i           ;  // Write Data Bus                to   FPGA
input       wire                WBs_CLK_i           ;  // FPGA Clock                    from FPGA
input       wire                WBs_RST_i           ;  // FPGA Reset                    to FPGA
output      wire    [31:0]      WBs_DAT_o           ;  // Read Data Bus                 from FPGA
output      wire                WBs_ACK_o           ;  // Transfer Cycle Acknowledge    from FPGA

// PWM clock
input       wire                Sys_clk             ;
input       wire                Sys_reset           ;

// PWM - 2:0 IOs only.
output      wire    [31:0]      BREATHE_o           ;

// Timer outputs, in this case interrupts
output      wire    [3:0]       TIMER_o             ; //TIMER_o[0] : interrupt

// LPC Slave Interface
input  wire        lpc_lclk         ; // LPC clock 33 Mhz
input  wire        lpc_lreset_n     ; // Reset - Active Low 
input  wire        lpc_lframe_n     ; // Frame - Active Low
inout  wire [ 3:0] lpc_lad_in       ; // Bi-directional 4-bit LAD bus (tri-state)	

// MODULE INTERNAL Signals ===============================================================

reg     [31:0]  BREATHE_0_CONFIG   = 32'h00000000;         
reg     [31:0]  BREATHE_1_CONFIG   = 32'h00000000;
reg     [31:0]  BREATHE_2_CONFIG   = 32'h00000000;     

wire            REG_WE_BREATHE_0_CONFIG     ;
wire            REG_WE_BREATHE_1_CONFIG     ;
wire            REG_WE_BREATHE_2_CONFIG     ;
wire            WBs_ACK_o_nxt               ;

reg     [31:0]  BREATHE_0_CONFIG_TMP   = 32'h00000000;         
reg     [31:0]  BREATHE_1_CONFIG_TMP   = 32'h00000000;
reg     [31:0]  BREATHE_2_CONFIG_TMP   = 32'h00000000;     

//--------------------------------------------------

//reg [19:0] cnt3 = 20'h00000;

// LPC Peripheral Inputs
wire        i_addr_hit_sig;
wire [ 7:0] i_din_sig;

// LPC Peripheral Outputs

reg  [ 4:0] o_current_state_sig;
reg  [ 7:0] o_lpc_data_in_sig;
wire [ 3:0] o_lpc_data_out_sig;
wire [15:0] o_lpc_addr_sig;
wire        o_lpc_en_sig;
wire        o_io_rden_sm_sig;
wire        o_io_wren_sm_sig;
reg  [31:0] TDATA_sig;
reg         READY_sig; 
//--------------------------
reg clock_33Mhz_enable;
wire [3:0] counter;
wire [3:0] divisor = 4'h3;

// MODULE LOGIC ==========================================================================

// define WRITE ENABLE logic:
assign REG_WE_BREATHE_0_CONFIG = ( WBs_ADR_i[ADDRWIDTH-1:2] == REG_ADDR_BREATHE_0_CONFIG[ADDRWIDTH-1:2] ) && 
                                                            WBs_CYC_i && 
                                                            WBs_STB_i && 
                                                            WBs_WE_i && 
                                                            (~WBs_ACK_o);

assign REG_WE_BREATHE_1_CONFIG = ( WBs_ADR_i[ADDRWIDTH-1:2] == REG_ADDR_BREATHE_1_CONFIG[ADDRWIDTH-1:2] ) && 
                                                            WBs_CYC_i && 
                                                            WBs_STB_i && 
                                                            WBs_WE_i && 
                                                            (~WBs_ACK_o);

assign REG_WE_BREATHE_2_CONFIG = ( WBs_ADR_i[ADDRWIDTH-1:2] == REG_ADDR_BREATHE_2_CONFIG[ADDRWIDTH-1:2] ) && 
                                                            WBs_CYC_i && 
                                                            WBs_STB_i && 
                                                            WBs_WE_i && 
                                                            (~WBs_ACK_o);


// define the ACK back to the host for registers
assign WBs_ACK_o_nxt  =  (WBs_CYC_i) && 
                         (WBs_STB_i) && 
                         (~WBs_ACK_o);

// define WRITE logic for the registers
always @( posedge WBs_CLK_i)
begin
//    if (WBs_RST_i)
//    begin
//        BREATHE_0_CONFIG                    <= 32'h00000010;
//        BREATHE_1_CONFIG                    <= 32'h00002000;
//        BREATHE_2_CONFIG                    <= 32'h03000000;
//        
//        cnt3 <= 20'h00000;
//        TIMER_o <= 4'b0000;
//    end  
//    else
        if (REG_WE_BREATHE_0_CONFIG)
        begin
            if (WBs_BYTE_STB_i[0])
                BREATHE_0_CONFIG[7:0]       <= WBs_DAT_i[7:0]   ;
            if (WBs_BYTE_STB_i[1])
                BREATHE_0_CONFIG[15:8]      <= WBs_DAT_i[15:8]  ;
            if (WBs_BYTE_STB_i[2])
                BREATHE_0_CONFIG[23:16]     <= WBs_DAT_i[23:16] ;
            if (WBs_BYTE_STB_i[3])
                BREATHE_0_CONFIG[31:24]     <= WBs_DAT_i[31:24] ;
        end
        
        if (REG_WE_BREATHE_1_CONFIG)
        begin
            if (WBs_BYTE_STB_i[0])
                BREATHE_1_CONFIG[7:0]       <= WBs_DAT_i[7:0]   ;
            if (WBs_BYTE_STB_i[1])
                BREATHE_1_CONFIG[15:8]      <= WBs_DAT_i[15:8]  ;
            if (WBs_BYTE_STB_i[2])
                BREATHE_1_CONFIG[23:16]     <= WBs_DAT_i[23:16] ;
            if (WBs_BYTE_STB_i[3])
                BREATHE_1_CONFIG[31:24]     <= WBs_DAT_i[31:24] ;
        end

        if (REG_WE_BREATHE_2_CONFIG)
        begin
            if (WBs_BYTE_STB_i[0])
                BREATHE_2_CONFIG[7:0]       <= WBs_DAT_i[7:0]   ;
            if (WBs_BYTE_STB_i[1])
                BREATHE_2_CONFIG[15:8]      <= WBs_DAT_i[15:8]  ;
            if (WBs_BYTE_STB_i[2])
                BREATHE_2_CONFIG[23:16]     <= WBs_DAT_i[23:16] ;
            if (WBs_BYTE_STB_i[3])
                BREATHE_2_CONFIG[31:24]     <= WBs_DAT_i[31:24] ;
       end
       WBs_ACK_o                               <=  WBs_ACK_o_nxt  ;

end

//generating clock_33Mhz_enable signal
always @(posedge WBs_CLK_i)
begin
  //if (WBs_CLK_i)
  //begin
    if (counter == divisor)
    begin
	  counter <= 4'b0000;
      clock_33Mhz_enable <= 1'b1;
	end
	else
	begin
	  clock_33Mhz_enable <= 1'b0;
      counter <= counter + 1'b1;
	end
  //end
end

// Logic for determine cycle type and send cycle data
always @( posedge WBs_CLK_i)
begin
  if (clock_33Mhz_enable)
  begin
     if (READY_sig)
     begin
	   BREATHE_0_CONFIG_TMP = TDATA_sig; //all cycle data sent in one 32-bit register
	   TIMER_o = 4'b1111;  //activate interrupt for MCU part
	 end
	 else
	 begin
	   TIMER_o = 4'b0000;  //deactivate interrupt for MCU part		
	 end
  end
  else TIMER_o = 4'b0000;
end 

// Logic for determine cycle type and send cycle data
//always @( posedge WBs_CLK_i)
//begin
//    if (lframe_i_sig == 1'b1)
//    begin	
//      was_new_frame = 1'b1; //New cycle started
//    end
//    if ((wbm_stb_o_sig==1'b1)&&(wbm_cyc_o_sig==1'b1)&&(was_new_frame==1'b1)) //cycle address and data ready
//    begin
//	  if (wbm_tga_o_sig==2'b01) //if this is TPM cycle
//	  begin
//	  	was_new_frame = 1'b0;
//        BREATHE_0_CONFIG_TMP = wbm_adr_o_sig;
//        BREATHE_1_CONFIG_TMP = wbm_dat_o_sig;
//        if (wbm_we_o_sig==1'b1) BREATHE_2_CONFIG_TMP = 32'h00000001; //write op
//        else BREATHE_2_CONFIG_TMP = 32'h00000000; //read op
//        TIMER_o = 4'b1111;  //activate interrupt for MCU part
//      end
//	end
//	else
//	begin
//	  TIMER_o = 4'b0000;  //deactivate interrupt for MCU part		
//    end
//end


//define READ logic for the registers
always @(*)
begin
    case(WBs_ADR_i[ADDRWIDTH-1:2])
        REG_ADDR_BREATHE_0_CONFIG    [ADDRWIDTH-1:2]    : WBs_DAT_o <= BREATHE_0_CONFIG_TMP ;
        REG_ADDR_BREATHE_1_CONFIG    [ADDRWIDTH-1:2]    : WBs_DAT_o <= BREATHE_1_CONFIG_TMP ;
        REG_ADDR_BREATHE_2_CONFIG    [ADDRWIDTH-1:2]    : WBs_DAT_o <= BREATHE_2_CONFIG_TMP ;
        default                                         : WBs_DAT_o <= DEFAULT_REG_VALUE    ;
    endcase
end

// Instantiate (sub)Modules ==============================================================

//***************************
// LPC Peripheral instantiation
//***************************
lpc_periph lpc_periph_inst(
// LPC Interface
.clk_i(lpc_lclk),
.nrst_i(lpc_lreset_n),
.lframe_i(lpc_lframe_n),
.lad_bus(lpc_lad_in),
.addr_hit_i(i_addr_hit_sig),
.current_state_o(o_current_peri_state_sig),
.din_i(i_din_sig),
.lpc_data_in_o(o_lpc_data_in_sig),
.lpc_data_out_o(o_lpc_data_out_sig),
.lpc_addr_o(o_lpc_addr_sig),
.lpc_en_o(o_lpc_en_sig),
.io_wren_sm_o(o_io_wren_sm_sig),
.io_rden_sm_o(o_io_wren_sm_sig),
//----------------------------------
.TDATA(TDATA_sig),
.READY(READY_sig)
);  
    
endmodule
