`include "Defines.vh"

module Fixed_Point_Unit 
#(
    parameter WIDTH = 32,
    parameter FBITS = 10
)
(
    input wire clk,
    input wire reset,
    
    input wire [WIDTH - 1 : 0] operand_1,
    input wire [WIDTH - 1 : 0] operand_2,
    
    input wire [ 1 : 0] operation,

    output reg [WIDTH - 1 : 0] result,
    output reg ready
);

    // Main combinational logic to perform the selected operation
    always @(*)
    begin
        case (operation)
            `FPU_ADD    : begin 
                              result <= operand_1 + operand_2; 
                              ready <= 1; 
                          end
            `FPU_SUB    : begin 
                              result <= operand_1 - operand_2; 
                              ready <= 1; 
                          end
            `FPU_MUL    : begin 
                              result <= product[WIDTH + FBITS - 1 : FBITS]; 
                              ready <= product_ready; 
                          end
            `FPU_SQRT   : begin 
                              result <= root; 
                              ready <= root_ready; 
                          end
            default     : begin 
                              result <= 'bz; 
                              ready <= 0; 
                          end
        endcase
    end

    // Reset logic
    always @(posedge reset)
    begin
        if (reset)  
            ready = 0;
        else        
            ready = 'bz;
    end

    // ------------------- //
    // Square Root Circuit //
    // ------------------- //
    reg [WIDTH - 1 : 0] root;
    reg root_ready;

    // State encoding for the sqrt state machine
    localparam IDLE = 2'b00, START = 2'b01, CALCULATE = 2'b10, DONE = 2'b11;

    reg [1 : 0] sqrt_state, sqrt_next_state;

    reg sqrt_start;
    reg sqrt_busy;
    
    reg [WIDTH - 1 : 0] x, x_next;              
    reg [WIDTH - 1 : 0] q, q_next;              
    reg [WIDTH + 1 : 0] ac, ac_next;            
    reg [WIDTH + 1 : 0] test_res;               

    reg [4 : 0] iteration = 0;

    // State transition for the square root state machine
    always @(posedge clk) 
    begin
        if (operation == `FPU_SQRT)
            sqrt_state <= sqrt_next_state;
        else
            sqrt_state <= IDLE;
            root_ready <= 0;
    end 

    // Next state logic for the square root state machine
    always @(*) 
    begin
        sqrt_next_state = sqrt_state;
        case (sqrt_state)
            IDLE: 
                if (operation == `FPU_SQRT)
                begin
                    sqrt_next_state = START;
                    sqrt_start <= 0;
                end
            START:
            begin
                sqrt_next_state = CALCULATE;
                sqrt_start <= 1;
            end
            CALCULATE:
            begin
                if (iteration == ((WIDTH + FBITS) >> 1) - 1)
                    sqrt_next_state = DONE;
                    sqrt_start <= 0;
            end
            DONE:
                sqrt_next_state = IDLE;
        endcase
    end                            

    // Combinational logic to perform one iteration of the square root calculation
    always @(*)
    begin
        test_res = ac - {q, 2'b01};

        if (test_res[WIDTH + 1] == 0) 
        begin
            {ac_next, x_next} = {test_res[WIDTH - 1 : 0], x, 2'b0};
            q_next = {q[WIDTH - 2 : 0], 1'b1};
        end 
        else 
        begin
            {ac_next, x_next} = {ac[WIDTH - 1 : 0], x, 2'b0};
            q_next = q << 1;
        end
    end
    
    // Sequential logic to update the square root state machine
    always @(posedge clk) 
    begin
        if (sqrt_start)
        begin
            sqrt_busy <= 1;
            root_ready <= 0;
            iteration <= 0;
            q <= 0;
            {ac, x} <= {{WIDTH{1'b0}}, operand_1, 2'b0};
        end

        else if (sqrt_busy)
        begin
            if (iteration == ((WIDTH + FBITS) >> 1)-1) 
            begin  // we're done
                sqrt_busy <= 0;
                root_ready <= 1;
                root <= q_next;
            end

            else 
            begin  // next iteration
                iteration <= iteration + 1;
                x <= x_next;
                ac <= ac_next;
                q <= q_next;
                root_ready <= 0;
            end
        end
    end

    // ------------------ //
    // Multiplier Circuit //
    // ------------------ //   
    reg [64 - 1 : 0] product;
    reg product_ready;

    reg [2:0] mul_state;
    
    reg [15 : 0] mul_op1, mul_op2;
    wire [31 : 0] mul_result;

    reg [31 : 0] P1, P2, P3, P4;

    // Multiplier module instantiation
    Multiplier multiplier
    (
        .operand_1(mul_op1),
        .operand_2(mul_op2),
        .product(mul_result)
    );

    // Sequential logic for the multiplication state machine
    always @(posedge clk or posedge reset)
    begin
        if (reset) begin
            mul_state <= 0;
            product_ready <= 0;
            product <= 0;
            {P1, P2, P3, P4} <= 0;
            {mul_op1, mul_op2} <= 0;
        end
        else if (operation == `FPU_MUL) begin
            case (mul_state)
                0: begin // A1 * B1
                    mul_op1 <= operand_1[15:0];
                    mul_op2 <= operand_2[15:0];
                    mul_state <= 1;
                end
                1: begin // A2 * B1
                    P1 <= mul_result;
                    mul_op1 <= operand_1[31:16];
                    mul_op2 <= operand_2[15:0];
                    mul_state <= 2;
                end
                2: begin // A1 * B2
                    P2 <= mul_result << 16;
                    mul_op1 <= operand_1[15:0];
                    mul_op2 <= operand_2[31:16];
                    mul_state <= 3;
                end
                3: begin // A2 * B2
                    P3 <= mul_result << 16;
                    mul_op1 <= operand_1[31:16];
                    mul_op2 <= operand_2[31:16];
                    mul_state <= 4;
                end
                4: begin // Combine results
                    P4 <= mul_result << 32;
                    mul_state <= 5;
                end
                5: begin
                    product <= P1 + P2 + P3 + P4;
                    product_ready <= 1;
                    mul_state <= 0;
                end
                default: mul_state <= 0;
            endcase
        end
    end
endmodule

// Multiplier module definition
module Multiplier
(
    input wire [15 : 0] operand_1,
    input wire [15 : 0] operand_2,

    output reg [31 : 0] product
);

    // Combinational logic to perform multiplication
    always @(*)
    begin
        product <= operand_1 * operand_2;
    end
endmodule
