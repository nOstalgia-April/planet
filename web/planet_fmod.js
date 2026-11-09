/* FMOD HTML5 2.03.06 bridge. The shell finishes loading banks before Godot starts. */
"use strict";
window.PlanetFmod = (() => {
    let fmod, studio, core;
    const banks = new Map();
    const api = {ready: false, errors: [], eventStarts: {}, version: "2.03.06"};
    function check(result) {
        if (result !== fmod.OK) {
            const message = fmod.ErrorString(result);
            api.errors.push(message);
            throw new Error("FMOD: " + message);
        }
    }
    function read(object, method, ...args) {
        const out = {};
        check(object[method](...args, out));
        return out.val;
    }
    class Event {
        constructor(raw, path = "") { this.raw = raw; this.path = path; }
        is_valid() { return this.raw.isValid(); }
        start() {
            check(this.raw.start());
            api.eventStarts[this.path] = (api.eventStarts[this.path] || 0) + 1;
        }
        stop(mode) { if (this.is_valid()) check(this.raw.stop(mode)); }
        release() { if (this.is_valid()) check(this.raw.release()); }
        set_volume(value) { if (this.is_valid()) check(this.raw.setVolume(value)); }
        set_paused(value) { if (this.is_valid()) check(this.raw.setPaused(value)); }
        set_parameter_by_name(name, value) {
            if (this.is_valid()) check(this.raw.setParameterByName(name, value, false));
        }
        get_timeline_position() { return this.is_valid() ? read(this.raw, "getTimelinePosition") : 0; }
        get_playback_state() { return this.is_valid() ? read(this.raw, "getPlaybackState") : fmod.STUDIO_PLAYBACK_STOPPED; }
    }
    class Description {
        constructor(raw) { this.raw = raw; }
        get_path() {
            const out = {};
            check(this.raw.getPath(out, 4096, null));
            return out.val;
        }
        get_length() { return read(this.raw, "getLength"); }
        get_instance_count() { return read(this.raw, "getInstanceCount"); }
        get_instance_list() {
            const count = this.get_instance_count();
            if (!count) return [];
            const out = {}, actual = {};
            check(this.raw.getInstanceList(out, count, actual));
            return out.val.map(raw => new Event(raw));
        }
        get_parameter_count() { return read(this.raw, "getParameterDescriptionCount"); }
        get_parameter_json(index) {
            const out = {};
            check(this.raw.getParameterDescriptionByIndex(index, out));
            return JSON.stringify(out);
        }
    }
    class Bank {
        constructor(raw) { this.raw = raw; }
        get_description_list() {
            const count = read(this.raw, "getEventCount");
            if (!count) return [];
            const out = {}, actual = {};
            check(this.raw.getEventList(out, count, actual));
            return out.val.map(raw => new Description(raw));
        }
    }
    api.initialize = (base = "fmod/") => new Promise((resolve, reject) => {
        fmod = {
            INITIAL_MEMORY: 128 * 1024 * 1024,
            locateFile: name => base + name,
            printErr: message => console.error(message),
            onAbort: reason => reject(new Error(String(reason))),
            preRun() {
                for (const name of ["Master.strings.bank", "Master.bank", "ProjectVacuum.bank"])
                    fmod.FS_createPreloadedFile("/", name, base + name, true, false);
            },
            onRuntimeInitialized() {
                try {
                    studio = read(fmod, "Studio_System_Create");
                    core = read(studio, "getCoreSystem");
                    check(core.setDSPBufferSize(2048, 2));
                    check(studio.initialize(512, fmod.STUDIO_INIT_NORMAL, fmod.INIT_NORMAL, null));
                    for (const name of ["Master.strings.bank", "Master.bank", "ProjectVacuum.bank"])
                        banks.set(name, new Bank(read(studio, "loadBankFile", "/" + name, fmod.STUDIO_LOAD_BANK_NORMAL)));
                    api.ready = true;
                    resolve();
                } catch (error) { reject(error); }
            }
        };
        FMODModule(fmod).catch(reject);
    });
    // Must run directly inside the shell's click handler (browser autoplay policy).
    api.unlock = () => {
        if (fmod.mContext) fmod.mContext.resume();
        if (fmod.context) fmod.context.resume();
    };
    api.load_bank = path => banks.get(path.split("/").pop());
    api.check_event_path = path => studio.getEvent(path, {}) === fmod.OK;
    api.check_bus_path = path => studio.getBus(path, {}) === fmod.OK;
    api.get_event = path => new Description(read(studio, "getEvent", path));
    api.create_event_instance = path => new Event(read(read(studio, "getEvent", path), "createInstance"), path);
    api.get_bus = path => {
        const raw = read(studio, "getBus", path);
        return {set_mute: value => check(raw.setMute(value))};
    };
    api.get_global_parameters_json = () => {
        const count = read(studio, "getParameterDescriptionCount"), result = [], actual = {};
        if (count) check(studio.getParameterDescriptionList(result, count, actual));
        return JSON.stringify(result);
    };
    api.set_global_parameter_by_name = (name, value) => check(studio.setParameterByName(name, value, false));
    api.update = () => { if (api.ready) check(studio.update()); };
    api.get_constant = name => fmod[name];
    api.shutdown = () => { if (api.ready) { api.ready = false; check(studio.release()); } };
    // Read-only verification: confirms actual PCM output, not only event state.
    api.audio_status = () => {
        const channels = {}; check(core.getChannelsPlaying(channels, null));
        return {channels: channels.val, context: (fmod.mContext || fmod.context).state, errors: api.errors.slice()};
    };
    window.addEventListener("pagehide", () => api.shutdown());
    return api;
})();
