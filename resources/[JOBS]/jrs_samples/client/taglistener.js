// Listens for the game's animal revive AI event and forwards it to client/main.lua
const EVENT_REVIVE = 1553659161;
const buffer = new ArrayBuffer(256);
const view = new DataView(buffer);

setTick(() => {
    const count = GetNumberOfEvents(0);
    for (let i = 0; i < count; i++) {
        if (GetEventAtIndex(0, i) !== EVENT_REVIVE) continue;
        Citizen.invokeNative('0x57EC5FA4D4D6AFCA', 0, i, view, 3, Citizen.returnResultAnyway());
        TriggerEvent('jrs_samples:ReviveData', new Int32Array(buffer)[2]);
    }
});
