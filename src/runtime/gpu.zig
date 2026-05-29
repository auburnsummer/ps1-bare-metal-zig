const psx = @import("ps1").registers;
const gpuc = @import("ps1").gpu_cmd;

pub fn waitForGp0Ready() void {
    while (!psx.GPU_STAT.cmd_ready) {}
}
