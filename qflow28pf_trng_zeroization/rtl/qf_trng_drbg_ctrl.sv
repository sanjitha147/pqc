// Q-FLOW28-PF Team A: TRNG/DRBG control and register view.
// Physical entropy source, source-specific health-test IP, conditioner, and approved
// DRBG core are external dependencies. This module is control RTL, not an entropy source.
module qf_trng_drbg_ctrl (
    input  logic clk_i,
    input  logic rst_ni,
    input  logic trng_enable_i,             // TRNG_CTRL[0]
    input  logic reseed_request_i,          // TRNG_CTRL[1], write-one-to-start pulse
    input  logic policy_allow_i,
    input  logic entropy_health_pass_i,     // source-specific startup + continuous health result
    input  logic entropy_health_running_i,
    input  logic health_fault_i,            // async source is expected to be synchronized upstream
    input  logic conditioned_seed_valid_i,
    input  logic [255:0] conditioned_seed_i, // PROPOSED width; align to selected DRBG standard
    input  logic random_req_i,
    input  logic [255:0] drbg_random_i,
    input  logic drbg_random_valid_i,
    input  logic drbg_busy_i,
    input  logic drbg_reseed_done_i,
    input  logic drbg_zeroize_busy_i,
    input  logic drbg_zeroize_req_i,
    input  logic zeroize_invalidate_i,

    output logic drbg_seed_valid_o,
    output logic [255:0] drbg_seed_o,
    output logic drbg_generate_req_o,
    output logic drbg_zeroize_req_o,
    output logic [255:0] random_data_o,
    output logic random_valid_o,
    output logic trng_ready_o,
    output logic drbg_busy_o,
    output logic health_pass_o,
    output logic health_fault_sticky_o,
    output logic reseed_required_o,
    output logic [31:0] reseed_count_o,
    output logic [31:0] trng_status_o,
    output logic [31:0] trng_health_o
);
    logic seed_pending_q;
    logic reseed_pending_q;
    logic drbg_seeded_q;
    logic [255:0] seed_q;

    // Sticky health failure; fail closed until reset/recovery mechanism is approved.
    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            health_fault_sticky_o <= 1'b0;
            seed_pending_q        <= 1'b0;
            reseed_pending_q      <= 1'b0;
            drbg_seeded_q         <= 1'b0;
            seed_q                <= '0;
            reseed_count_o        <= 32'd0;
        end else begin
            if (health_fault_i) begin
                health_fault_sticky_o <= 1'b1;
                drbg_seeded_q         <= 1'b0;
            end
            if (zeroize_invalidate_i || drbg_zeroize_req_i) begin
                seed_pending_q   <= 1'b0;
                reseed_pending_q <= 1'b0;
                drbg_seeded_q    <= 1'b0;
                seed_q           <= '0;
            end else begin
                if (reseed_request_i && trng_enable_i && policy_allow_i &&
                    entropy_health_pass_i && !health_fault_sticky_o && !health_fault_i) begin
                    reseed_pending_q <= 1'b1;
                end
                if (conditioned_seed_valid_i && reseed_pending_q &&
                    entropy_health_pass_i && !health_fault_sticky_o && !health_fault_i) begin
                    seed_q           <= conditioned_seed_i;
                    seed_pending_q   <= 1'b1;
                    reseed_pending_q <= 1'b0;
                end
                if (drbg_reseed_done_i && seed_pending_q &&
                    entropy_health_pass_i && !health_fault_sticky_o && !health_fault_i) begin
                    reseed_count_o <= reseed_count_o + 32'd1;
                    seed_pending_q <= 1'b0;
                    drbg_seeded_q  <= 1'b1;
                end
            end
        end
    end

    assign health_pass_o = entropy_health_pass_i && !health_fault_sticky_o;
    // Reseed is required whenever DRBG is not currently seeded (initial boot or post-zeroize) or health fails
    assign reseed_required_o = !drbg_seeded_q || !health_pass_o;
    assign trng_ready_o = trng_enable_i && policy_allow_i && health_pass_o &&
                          !entropy_health_running_i && !reseed_required_o &&
                          !drbg_zeroize_req_i && !zeroize_invalidate_i;
    assign drbg_seed_valid_o = seed_pending_q && health_pass_o && policy_allow_i && !drbg_zeroize_req_i;
    assign drbg_seed_o = drbg_seed_valid_o ? seed_q : '0;
    assign drbg_generate_req_o = random_req_i && trng_ready_o && !drbg_busy_i && !drbg_zeroize_req_i;
    assign drbg_zeroize_req_o = drbg_zeroize_req_i;
    assign random_valid_o = drbg_random_valid_i && trng_ready_o && !drbg_zeroize_req_i && !zeroize_invalidate_i;
    assign random_data_o = random_valid_o ? drbg_random_i : '0;
    assign drbg_busy_o = drbg_busy_i | reseed_pending_q | seed_pending_q | drbg_zeroize_busy_i;

    // Register bit assignments from COMMON_REGISTER_MAP_v1.0.
    // TRNG_STATUS: ready[0], drbg_busy[1], health_pass[2], health_fault[3], reseed_required[4].
    // TRNG_HEALTH: test_pass[0], test_running[1], sticky_fault[2].
    always_comb begin
        trng_status_o = 32'd0;
        trng_status_o[0] = trng_ready_o;
        trng_status_o[1] = drbg_busy_o;
        trng_status_o[2] = health_pass_o;
        trng_status_o[3] = health_fault_sticky_o;
        trng_status_o[4] = reseed_required_o;
        trng_health_o = 32'd0;
        trng_health_o[0] = health_pass_o;
        trng_health_o[1] = entropy_health_running_i;
        trng_health_o[2] = health_fault_sticky_o;
    end
endmodule
