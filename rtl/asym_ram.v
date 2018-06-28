module asym_ram(clkA, clkB, weA, addrA, addrB, dinA, doutB);
    parameter WIDTHB = 48;
    parameter SIZEB = 1024;
    parameter ADDRWIDTHB = 10;
    parameter WIDTHA = 384;
    parameter SIZEA = 128;
    parameter ADDRWIDTHA = 7;

    input clkA;
    input clkB;
    input weA;
    input [ADDRWIDTHA-1:0] addrA;
    input [ADDRWIDTHB-1:0] addrB;
    input [WIDTHA-1:0] dinA;
    output [WIDTHB-1:0] doutB;

    `define max(a,b) {(a) > (b) ? (a) : (b)}
    `define min(a,b) {(a) < (b) ? (a) : (b)}

    function integer log2;
        input integer value;
        reg [31:0] shifted;
        integer res;
        begin
            if (value < 2)
                log2 = value;
            else
            begin
                shifted = value - 1;
                for (res = 0; shifted > 0; res = res + 1)
                    shifted = shifted >> 1;
                log2 = res;
            end
        end
    endfunction

    localparam maxSIZE = `max(SIZEA, SIZEB);
    localparam maxWIDTH = `max(WIDTHA, WIDTHB);
    localparam minWIDTH = `min(WIDTHA, WIDTHB);
    localparam RATIO = maxWIDTH / minWIDTH;
    localparam log2RATIO = log2(RATIO);

    reg [minWIDTH - 1:0] RAM [0:maxSIZE - 1];
    reg [WIDTHB - 1:0] readB;

    always @(posedge clkB) begin
        readB <= RAM[addrB];
    end

    assign doutB = readB;

    always @(posedge clkA)
    begin: ramwrite
        integer i;
        reg [log2RATIO-1:0] lsbaddr;

        for (i = 0; i < RATIO; i = i + 1)
        begin : write1
            lsbaddr = i;
            if (weA)
            begin
                RAM[{addrA, lsbaddr}] <= dinA[(i+1)*minWIDTH-1 -: minWIDTH];
            end
        end
    end
endmodule
