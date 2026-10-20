// Q-FLOW28-PF Team A: shared zeroisation sequencer
// Architecture frozen by project spec: abort -> zeroize -> invalidate -> record.
// Handshake: each participant accepts a one-cycle request pulse, asserts zeroize_busy
// while scrubbing, and deasserts it when complete.
// Includes a timeout watchdog to prevent permanent deadlock if a participant is idle/unresponsive.
module qf_zeroize_ctrl #(
    parameter int unsigned TIMEOUT_CYCLES = 64
) (
    input  logic clk_i,
    input  logic rst_ni,
    input  logic ctx_clear_req_i,
    input  logic security_fault_i,
    input  logic tamper_i,
    input  logic fatal_integrity_i,
    input  logic txn_active_i,

    input  logic kv_zeroize_busy_i,
    input  logic ctx_zeroize_busy_i,
    input  logic scratch_zeroize_busy_i,
    input  logic drbg_zeroize_busy_i,

    output logic txn_abort_o,
    output logic kv_zeroize_req_o,
    output logic ctx_zeroize_req_o,
    output logic scratch_zeroize_req_o,
    output logic drbg_zeroize_req_o,
    output logic invalidate_req_o,
    output logic event_record_o,
    output logic zeroize_active_o,
    output logic zeroize_done_o,
    output logic fault_latched_o
);
    typedef enum logic [2:0] {
        Z_IDLE, Z_ABORT, Z_REQUEST, Z_WAIT, Z_INVALIDATE, Z_RECORD
    } zstate_t;
    zstate_t state_q, state_d;
    logic [3:0] busy_seen_q;
    logic [3:0] busy_now;
    logic trigger_now;
    logic fault_trigger_now;
    logic [$clog2(TIMEOUT_CYCLES+1)-1:0] timeout_cnt_q;

    assign busy_now = {drbg_zeroize_busy_i, scratch_zeroize_busy_i,
                       ctx_zeroize_busy_i, kv_zeroize_busy_i};
    assign trigger_now = ctx_clear_req_i | security_fault_i | tamper_i | fatal_integrity_i;
    assign fault_trigger_now = security_fault_i | tamper_i | fatal_integrity_i;

    always_comb begin
        state_d = state_q;
        unique case (state_q)
            Z_IDLE:       if (trigger_now) state_d = Z_ABORT;
            Z_ABORT:      state_d = Z_REQUEST;
            Z_REQUEST:    state_d = Z_WAIT;
            Z_WAIT: begin
                // Transition to INVALIDATE when:
                // 1) All 4 participants have asserted busy and subsequently completed, OR
                // 2) Safety timeout expires (e.g. an idle block had nothing to scrub) and all active scrubs are done
                if (((&busy_seen_q) && !(|busy_now)) || ((timeout_cnt_q >= TIMEOUT_CYCLES) && !(|busy_now))) begin
                    state_d = Z_INVALIDATE;
                end
            end
            Z_INVALIDATE: state_d = Z_RECORD;
            Z_RECORD:     state_d = Z_IDLE;
            default:      state_d = Z_ABORT; // fail closed on illegal state
        endcase
    end

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            state_q         <= Z_IDLE;
            busy_seen_q     <= 4'b0000;
            timeout_cnt_q   <= '0;
            fault_latched_o <= 1'b0;
        end else begin
            state_q <= state_d;
            if (fault_trigger_now) fault_latched_o <= 1'b1;

            if (state_q == Z_IDLE || state_q == Z_REQUEST) begin
                busy_seen_q   <= 4'b0000;
                timeout_cnt_q <= '0;
            end else if (state_q == Z_WAIT) begin
                busy_seen_q   <= busy_seen_q | busy_now;
                if (timeout_cnt_q < TIMEOUT_CYCLES) begin
                    timeout_cnt_q <= timeout_cnt_q + 1'b1;
                end
            end
            // fault_latched_o is sticky until reset; software cannot clear a security fault.
        end
    end

    always_comb begin
        txn_abort_o           = 1'b0;
        kv_zeroize_req_o      = 1'b0;
        ctx_zeroize_req_o     = 1'b0;
        scratch_zeroize_req_o = 1'b0;
        drbg_zeroize_req_o    = 1'b0;
        invalidate_req_o      = 1'b0;
        event_record_o        = 1'b0;
        zeroize_active_o      = (state_q != Z_IDLE);
        zeroize_done_o        = 1'b0;
        unique case (state_q)
            Z_ABORT: begin
                txn_abort_o = txn_active_i;
            end
            Z_REQUEST: begin
                // One-cycle request pulses; each participant must latch the request.
                kv_zeroize_req_o      = 1'b1;
                ctx_zeroize_req_o     = 1'b1;
                scratch_zeroize_req_o = 1'b1;
                drbg_zeroize_req_o    = 1'b1;
            end
            Z_INVALIDATE: invalidate_req_o = 1'b1;
            Z_RECORD: begin
                event_record_o = 1'b1;
                zeroize_done_o = 1'b1;
            end
            default: ;
        endcase
    end
endmodule
