// jrs_fishing | client | bridge to the game's fishing task
// The task keeps its state in a block of 8-byte slots. Lua can not read raw memory, so this file reads the
// block, hands the slots over as two views (ints and floats), and writes a table of slots back.

const FLOAT_SLOTS = new Set([1, 2, 3, 4, 8, 9, 13, 14, 15, 17, 20, 21, 22, 23, 24, 25, 26, 27]);
const READ_TASK = '0xF3735ACD11ACD500';
const WRITE_TASK = '0xF3735ACD11ACD501';

// floats go into the block as their raw 32-bit pattern
function floatBits(value) {
    const scratch = new DataView(new ArrayBuffer(4));
    scratch.setFloat32(0, value, false);
    return scratch.getInt32(0, false);
}

function readBlock(size) {
    const buffer = new ArrayBuffer(size);
    const view = new DataView(buffer);
    const active = Citizen.invokeNative(READ_TASK, PlayerPedId(), view);
    return [active, new Int32Array(buffer), new Float32Array(buffer)];
}

function writeBlock(size, slots, slotCount) {
    const view = new DataView(new ArrayBuffer(size));
    for (let i = 0; i < slotCount; i++) {
        let value = slots[`f_${i}`];
        if (FLOAT_SLOTS.has(i) && i <= (slotCount > 22 ? 27 : 21)) value = floatBits(value);
        view.setUint32(i * 8, value, true);
    }
    Citizen.invokeNative(WRITE_TASK, PlayerPedId(), view);
}

exports('GET_TASK_FISHING_DATA_EXTRA', () => readBlock(256));
exports('SET_TASK_FISHING_DATA_EXTRA', (slots) => writeBlock(256, slots, 28));

// the short form only knows the first 22 slots
exports('GET_TASK_FISHING_DATA', () => {
    const [active, ints, floats] = readBlock(8 * 28);
    return [active, ints, floats];
});
exports('SET_TASK_FISHING_DATA', (slots) => writeBlock(8 * 28, slots, 22));

// height of the water surface above/below a point
exports('VERTICAL_PROBE', (x, y, z, flag) => {
    const buffer = new ArrayBuffer(8);
    const hit = Citizen.invokeNative('0x2B3451FA1E3142E2', x, y, z, flag, new DataView(buffer));
    return [hit, new Float32Array(buffer)[0]];
});
