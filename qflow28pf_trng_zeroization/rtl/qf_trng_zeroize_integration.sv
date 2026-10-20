// Thin integration shell showing the Team A TRNG/DRBG control and shared zeroizer.
// KV/context/scratchpad/DRBG participants are external blocks; their busy/acceptance
// behavior must follow the handshake described in docs/README.md.
module qf_trng_zeroize_integration (
    input  logic clk_i, rst_ni,
    input  logic ctx_clear_req_i, security_fault_i, tamper_i, fatal_integrity_i,
    input  logic txn_active_i,
    input  logic kv_zeroize_busy_i, ctx_zeroize_busy_i, scratch_zeroize_busy_i,
    input  logic drbg_zeroize_busy_i,
    input  logic trng_enable_i, reseed_request_i, policy_allow_i,
    input  logic entropy_health_pass_i, entropy_health_running_i, health_fault_i,
    input  logic conditioned_seed_valid_i,
    input  logic [255:0] conditioned_seed_i,
    input  logic random_req_i,
    input  logic [255:0] drbg_random_i,
    input  logic drbg_random_valid_i, drbg_busy_i, drbg_reseed_done_i,
    output logic txn_abort_o, kv_zeroize_req_o, ctx_zeroize_req_o,
    output logic scratch_zeroize_req_o, drbg_zeroize_req_o,
    output logic invalidate_req_o, event_record_o, zeroize_active_o, zeroize_done_o,
    output logic drbg_seed_valid_o,
    output logic [255:0] drbg_seed_o,
    output logic drbg_generate_req_o,
    output logic [255:0] random_data_o,
    output logic random_valid_o,
    output logic trng_ready_o,
    output logic drbg_busy_o,
    output logic health_pass_o,
    output logic health_fault_sticky_o,
    output logic reseed_required_o,
    output logic [31:0] trng_status_o,
    output logic [31:0] trng_health_o,
    output logic [31:0] reseed_count_o,
    output logic fault_latched_o
);
    logic zeroize_to_trng_req;

    qf_zeroize_ctrl u_zeroize (
        .clk_i, .rst_ni, .ctx_clear_req_i, .security_fault_i, .tamper_i, .fatal_integrity_i,
        .txn_active_i, .kv_zeroize_busy_i, .ctx_zeroize_busy_i, .scratch_zeroize_busy_i,
        .drbg_zeroize_busy_i, .txn_abort_o, .kv_zeroize_req_o, .ctx_zeroize_req_o,
        .scratch_zeroize_req_o, .drbg_zeroize_req_o(zeroize_to_trng_req),
        .invalidate_req_o, .event_record_o,
        .zeroize_active_o, .zeroize_done_o, .fault_latched_o
    );

    qf_trng_drbg_ctrl u_trng_ctrl (
        .clk_i, .rst_ni, .trng_enable_i, .reseed_request_i, .policy_allow_i,
        .entropy_health_pass_i, .entropy_health_running_i, .health_fault_i,
        .conditioned_seed_valid_i, .conditioned_seed_i, .random_req_i, .drbg_random_i,
        .drbg_random_valid_i, .drbg_busy_i, .drbg_reseed_done_i, .drbg_zeroize_busy_i,
        .drbg_zeroize_req_i(zeroize_to_trng_req), .zeroize_invalidate_i(invalidate_req_o),
        .drbg_seed_valid_o, .drbg_seed_o,
        .drbg_generate_req_o, .drbg_zeroize_req_o(drbg_zeroize_req_o),
        .random_data_o, .random_valid_o, .trng_ready_o, .drbg_busy_o,
        .health_pass_o, .health_fault_sticky_o,
        .reseed_required_o, .reseed_count_o,
        .trng_status_o, .trng_health_o
    );
endmodule
