/* -------------------------------------------------------------------------
   Planet: procedural suction events

   Adds a "Planet Audio" menu to FMOD Studio with two items:
   - Build Procedural Suction Events: creates three events in event:/Vacuum
     and assigns them to the ProjectVacuum bank.
       Vacuum_Suck     parameter Suck_Progress 0-1 (the suction progress bar)
       Mucus_Peel      parameter Peel_Progress 0-1 (pulling off the mucus)
       Mucus_PeelSnap  one-shot, for the moment the monster comes free
     Every layer is a synthesized loop from tools/fmod_procedural/sources;
     filters, pitch and volume follow the progress parameter, so the sound
     tracks the bar however long the suction takes.
   - Remove Procedural Suction Events: deletes those three events again.

   Install: copy this file into ProjectVacuum_FMOD/Scripts/, then
   Scripts > Reload in FMOD Studio. Nothing is saved automatically.
   ------------------------------------------------------------------------- */

var SCRIPT_DIR = __dirname;

(function () {
    var FOLDER_PATH = "event:/Vacuum";
    var BANK_PATH = "bank:/ProjectVacuum";
    var ASSET_FOLDER = "Procedural";

    // Multiband EQ filter types (band A).
    var LOWPASS_24DB = 2;
    var BANDPASS = 10;

    // Points are [progress, value]; volume in dB, pitch in semitones,
    // frequency in Hz.
    var LOOP_EVENTS = [
        {
            name: "Vacuum_Suck",
            parameter: "Suck_Progress",
            attackMs: 40,
            releaseMs: 150,
            tracks: [
                {
                    name: "Air",
                    file: "suck_air_loop.wav",
                    volume: [[0, -12], [0.15, -6], [1, -1]],
                    eq: {
                        type: BANDPASS,
                        frequency: [[0, 350], [0.6, 1200], [0.9, 2600], [1, 3200]],
                        quality: [[0, 0.9], [1, 2.5]],
                    },
                },
                {
                    name: "Motor",
                    file: "suck_motor_loop.wav",
                    volume: [[0, -14], [1, -6]],
                    pitch: [[0, 0], [0.7, 5], [1, 9]],
                    eq: { type: LOWPASS_24DB, frequency: [[0, 900], [1, 2400]] },
                },
                {
                    name: "Gurgle",
                    file: "suck_gurgle_loop.wav",
                    volume: [[0, -40], [0.4, -24], [0.85, -8], [1, -4]],
                    pitch: [[0, -2], [1, 4]],
                },
            ],
        },
        {
            name: "Mucus_Peel",
            parameter: "Peel_Progress",
            attackMs: 30,
            releaseMs: 80,
            tracks: [
                {
                    name: "Goo",
                    file: "peel_goo_loop.wav",
                    volume: [[0, -8], [1, -2]],
                    eq: { type: LOWPASS_24DB, frequency: [[0, 220], [0.7, 480], [1, 800]] },
                },
                {
                    name: "Squelch Sparse",
                    file: "peel_squelch_sparse_loop.wav",
                    volume: [[0, -4], [0.5, -8], [1, -30]],
                },
                {
                    name: "Squelch Dense",
                    file: "peel_squelch_dense_loop.wav",
                    volume: [[0, -30], [0.5, -9], [1, -3]],
                    pitch: [[0, 0], [1, 3]],
                },
                {
                    name: "Stretch",
                    file: "peel_stretch_loop.wav",
                    volume: [[0, -24], [0.6, -12], [1, -4]],
                    pitch: [[0, -3], [1, 7]],
                },
            ],
        },
    ];

    var ONE_SHOT_EVENTS = [
        { name: "Mucus_PeelSnap", file: "peel_snap.wav", length: 0.6 },
    ];

    function allEventNames() {
        return LOOP_EVENTS.concat(ONE_SHOT_EVENTS).map(function (spec) { return spec.name; });
    }

    function findSourceDir() {
        // Installed as ProjectVacuum_FMOD/Scripts/, beside the planet/ game folder.
        var candidates = [
            SCRIPT_DIR + "/../../planet/tools/fmod_procedural/sources",
            SCRIPT_DIR + "/fmod_procedural/sources",
            SCRIPT_DIR + "/sources",
        ];
        var projectFile = studio.project.filePath || studio.project.filepath;
        if (projectFile) {
            var projectDir = String(projectFile).replace(/[\/\\][^\/\\]*$/, "");
            candidates.push(projectDir + "/../planet/tools/fmod_procedural/sources");
        }
        for (var i = 0; i < candidates.length; i++) {
            if (studio.system.getFile(candidates[i] + "/suck_air_loop.wav").exists()) {
                return candidates[i];
            }
        }
        return null;
    }

    // Studio property names are not all documented; set the first one present.
    function setProperty(object, names, value, warnings, label) {
        for (var i = 0; i < names.length; i++) {
            if (object.properties[names[i]] !== undefined) {
                object[names[i]] = value;
                return true;
            }
        }
        warnings.push(label + ": no property named " + names.join(" / "));
        return false;
    }

    function importAsset(sourceDir, fileName) {
        var folder = studio.project.workspace.masterAssetFolder;
        var existing = folder.getAsset(ASSET_FOLDER + "/" + fileName) || folder.getAsset(fileName);
        if (existing) {
            return existing;
        }
        var asset = studio.project.importAudioFile(sourceDir + "/" + fileName);
        if (!asset) {
            throw new Error("could not import " + fileName);
        }
        asset.setAssetPath(ASSET_FOLDER + "/" + fileName);
        return asset;
    }

    function automate(track, target, propertyName, parameter, points, warnings, label) {
        try {
            var automationTrack = track.addAutomationTrack(target, propertyName);
            var automator = automationTrack ? automationTrack.automator : null;
            if (!automator) {
                automator = target.addAutomator(propertyName);
                if (automationTrack) {
                    automationTrack.automator = automator;
                }
            }
            var curve = automator.addAutomationCurve(parameter);
            points.forEach(function (point) {
                curve.addAutomationPoint(point[0], point[1]);
            });
        } catch (error) {
            warnings.push(label + " " + propertyName + " automation: " + error);
        }
    }

    function createEvent(name, folder, bank) {
        var event = studio.project.workspace.addEvent(name, false);
        event.folder = folder;
        if (bank) {
            event.relationships.banks.add(bank);
        }
        return event;
    }

    // Instruments go on the event's parameter sheet (its ParameterProxy);
    // automation curves go on the GameParameter behind it.
    function parameterParts(event, added) {
        var proxy = added.isOfType("ParameterProxy") ? added : null;
        if (!proxy) {
            event.parameters.forEach(function (candidate) {
                var preset = candidate.preset;
                if (preset === added || (preset && preset.parameter === added)) {
                    proxy = candidate;
                }
            });
        }
        if (!proxy) {
            throw new Error("parameter sheet not found");
        }
        return { sheet: proxy, curveParameter: proxy.preset.parameter };
    }

    function buildLoopEvent(spec, folder, bank, sourceDir, warnings) {
        var event = createEvent(spec.name, folder, bank);
        var parts = parameterParts(event, event.addGameParameter({
            name: spec.parameter,
            type: studio.project.parameterType.User,
            min: 0,
            max: 1,
        }));
        var sheet = parts.sheet;
        var curveParameter = parts.curveParameter;

        spec.tracks.forEach(function (trackSpec) {
            var label = spec.name + "/" + trackSpec.name;
            var track = event.addGroupTrack(trackSpec.name);
            var sound = track.addSound(sheet, "SingleSound", 0, 1);
            if (!sound) {
                throw new Error(trackSpec.name + ": could not place the instrument on " + spec.parameter);
            }
            sound.audioFile = importAsset(sourceDir, trackSpec.file);
            setProperty(sound, ["looping", "isLooping"], true, warnings, label + " loop");

            automate(track, track.mixerGroup, "volume", curveParameter, trackSpec.volume, warnings, label);
            if (trackSpec.pitch) {
                automate(track, sound, "pitch", curveParameter, trackSpec.pitch, warnings, label);
            }
            if (trackSpec.eq) {
                var eq = track.mixerGroup.effectChain.addEffect("MultibandEqEffect");
                eq.filterTypeA = trackSpec.eq.type;
                automate(track, eq, "frequencyA", curveParameter, trackSpec.eq.frequency, warnings, label);
                if (trackSpec.eq.quality) {
                    automate(track, eq, "qualityA", curveParameter, trackSpec.eq.quality, warnings, label);
                }
            }
        });

        // Short fade in on start and fade out on stop, so letting go never clicks.
        try {
            var envelope = event.masterTrack.mixerGroup.addModulator("ADSRModulator", "volume");
            setProperty(envelope, ["initialValue"], -80, warnings, spec.name + " AHDSR");
            setProperty(envelope, ["attackTime"], spec.attackMs, warnings, spec.name + " AHDSR");
            setProperty(envelope, ["releaseTime"], spec.releaseMs, warnings, spec.name + " AHDSR");
            setProperty(envelope, ["finalValue"], -80, warnings, spec.name + " AHDSR");
        } catch (error) {
            warnings.push(spec.name + " AHDSR: " + error);
        }
        return event;
    }

    function buildOneShotEvent(spec, folder, bank, sourceDir) {
        var event = createEvent(spec.name, folder, bank);
        var track = event.addGroupTrack("Snap");
        var sound = track.addSound(event.timeline, "SingleSound", 0, spec.length);
        sound.audioFile = importAsset(sourceDir, spec.file);
        return event;
    }

    function build() {
        var folder = studio.project.lookup(FOLDER_PATH);
        if (!folder) {
            alert("Event folder " + FOLDER_PATH + " not found.");
            return;
        }
        var existing = allEventNames().filter(function (name) {
            return studio.project.lookup(FOLDER_PATH + "/" + name);
        });
        if (existing.length > 0) {
            alert("Already in the project: " + existing.join(", ") +
                "\nUse Planet Audio > Remove Procedural Suction Events first to rebuild.");
            return;
        }
        var sourceDir = findSourceDir();
        if (!sourceDir) {
            alert("Source WAVs not found. Expected planet/tools/fmod_procedural/sources " +
                "next to the FMOD project folder.");
            return;
        }
        var bank = studio.project.lookup(BANK_PATH);
        var warnings = [];
        if (!bank) {
            warnings.push("Bank " + BANK_PATH + " not found; assign the events to a bank by hand.");
        }

        var built = [];
        LOOP_EVENTS.forEach(function (spec) {
            try {
                built.push(buildLoopEvent(spec, folder, bank, sourceDir, warnings));
            } catch (error) {
                warnings.push(spec.name + " stopped: " + error);
            }
        });
        ONE_SHOT_EVENTS.forEach(function (spec) {
            try {
                built.push(buildOneShotEvent(spec, folder, bank, sourceDir));
            } catch (error) {
                warnings.push(spec.name + " stopped: " + error);
            }
        });

        warnings.forEach(function (warning) { console.warn(warning); });
        if (built.length > 0) {
            studio.window.navigateTo(built[0]);
        }
        alert("Built " + built.length + " event(s) in " + FOLDER_PATH + "." +
            (warnings.length > 0
                ? "\n\nWarnings (also in Window > Console):\n" + warnings.join("\n")
                : "\nNo warnings.") +
            "\n\nThe project is not saved yet.");
    }

    function remove() {
        var events = allEventNames()
            .map(function (name) { return studio.project.lookup(FOLDER_PATH + "/" + name); })
            .filter(function (event) { return event; });
        if (events.length === 0) {
            alert("No procedural suction events to remove.");
            return;
        }
        var names = events.map(function (event) { return event.name; }).join(", ");
        if (!studio.system.question("Delete " + names + "? Imported WAVs stay in the Assets browser.")) {
            return;
        }
        events.forEach(function (event) { studio.project.deleteObject(event); });
        alert("Removed " + names + ".");
    }

    studio.menu.addMenuItem({
        name: "Planet Audio\\Build Procedural Suction Events",
        execute: build,
    });
    studio.menu.addMenuItem({
        name: "Planet Audio\\Remove Procedural Suction Events",
        execute: remove,
    });
})();
