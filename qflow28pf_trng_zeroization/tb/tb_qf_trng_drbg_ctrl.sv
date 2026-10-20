`timescale 1ns/1ps
module tb_qf_trng_drbg_ctrl;
  logic clk=0; always #5 clk=~clk;
  logic rst_n=0, enable=0, reseed_req=0, policy=1, health_pass=0, health_running=1, health_fault=0;
  logic seed_valid=0, random_req=0, random_valid_i=0, drbg_busy=0, reseed_done=0, zeroize_busy=0, zeroize_req=0, invalidate=0;
  logic [255:0] seed='h1234, random_i='hbeef;
  logic seed_valid_o, gen_req, zeroize_req_o, random_valid_o, ready, busy_o, health_pass_o, fault_sticky, reseed_required;
  logic [255:0] seed_o, random_o; logic [31:0] reseed_count, status, health;
  qf_trng_drbg_ctrl dut(.clk_i(clk),.rst_ni(rst_n),.trng_enable_i(enable),.reseed_request_i(reseed_req),
    .policy_allow_i(policy),.entropy_health_pass_i(health_pass),.entropy_health_running_i(health_running),
    .health_fault_i(health_fault),.conditioned_seed_valid_i(seed_valid),.conditioned_seed_i(seed),
    .random_req_i(random_req),.drbg_random_i(random_i),.drbg_random_valid_i(random_valid_i),
    .drbg_busy_i(drbg_busy),.drbg_reseed_done_i(reseed_done),.drbg_zeroize_busy_i(zeroize_busy),
    .drbg_zeroize_req_i(zeroize_req),.zeroize_invalidate_i(invalidate),.drbg_seed_valid_o(seed_valid_o),
    .drbg_seed_o(seed_o),.drbg_generate_req_o(gen_req),.drbg_zeroize_req_o(zeroize_req_o),
    .random_data_o(random_o),.random_valid_o(random_valid_o),.trng_ready_o(ready),.drbg_busy_o(busy_o),
    .health_pass_o(health_pass_o),.health_fault_sticky_o(fault_sticky),.reseed_required_o(reseed_required),
    .reseed_count_o(reseed_count),.trng_status_o(status),.trng_health_o(health));
  task automatic tick(input int n); repeat(n) @(posedge clk); #1; endtask
  initial begin
    tick(2); rst_n=1; tick(1);
    enable=1; health_running=0; health_pass=1; reseed_req=1; tick(1); reseed_req=0;
    seed_valid=1; tick(1); seed_valid=0;
    // 1. Gate output before a completed reseed: random data must NOT be valid before reseed completes
    random_req=1; random_valid_i=1; tick(1);
    if (random_valid_o || ready) $fatal(1,"output escaped before initial reseed completed");
    // 2. Complete reseed and verify output passes
    reseed_done=1; tick(1); reseed_done=0; tick(1);
    random_req=1; random_valid_i=1; tick(1);
    if (!random_valid_o || !ready || (reseed_count != 32'd1)) $fatal(1,"healthy random output did not pass gate");
    // 3. Test zeroization clears seeded state while preserving reseed_count telemetry
    zeroize_req=1; tick(1); zeroize_req=0; tick(1);
    if (random_valid_o || ready || !reseed_required || (reseed_count != 32'd1)) $fatal(1,"post-zeroize did not force reseed_required");
    // 4. Re-seed after zeroize and test sticky health fault
    reseed_req=1; tick(1); reseed_req=0;
    seed_valid=1; tick(1); seed_valid=0;
    reseed_done=1; tick(1); reseed_done=0; tick(1);
    if (!ready || (reseed_count != 32'd2)) $fatal(1,"re-seed after zeroize failed");
    health_fault=1; tick(1); health_fault=0; tick(1);
    if (random_valid_o || !fault_sticky || ready) $fatal(1,"health failure did not block output and latch");
    $display("PASS: TRNG health gate, reseed status, post-zeroize reseed requirement, and output suppression on health fault"); $finish;
  end
endmodule
