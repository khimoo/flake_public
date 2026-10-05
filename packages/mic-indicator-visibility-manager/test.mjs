import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import test from 'node:test';
import vm from 'node:vm';
import {shouldShowInput} from './filter.js';

const settings = {
    get_boolean: () => true,
    get_strv: key => key === 'skipped-apps'
        ? ['org.gnome.VolumeControl', 'org.PulseAudio.pavucontrol']
        : ['node.name:echo-cancel-capture', 'node.name:echo-cancel-reference'],
};
const capture = {properties: {'node.name': 'echo-cancel-capture', 'node.virtual': 'true'}};
const reference = {properties: {'node.name': 'echo-cancel-reference', 'node.virtual': 'true'}};

test('AEC alone does not indicate application microphone use', () => {
    assert.equal(shouldShowInput([capture, reference], settings), false);
});
test('an application using the virtual microphone still indicates use', () => {
    const app = {properties: {'node.name': 'browser-recording', 'node.virtual': 'true'}};
    assert.equal(shouldShowInput([capture, reference, app], settings), true);
});
test('volume-control level meters are excluded but a physical recorder is visible', () => {
    const meter = {properties: {'application.id': 'org.PulseAudio.pavucontrol'}};
    assert.equal(shouldShowInput([capture, reference, meter], settings), false);
    assert.equal(shouldShowInput([meter, {properties: {'node.name': 'recorder'}}], settings), true);
});
test('malformed data fails instead of silently hiding microphone use', () => {
    for (const invalid of [null, {}, [null], [{}], [{properties: null}]])
        assert.throws(() => shouldShowInput(invalid, settings));
});

// Shell and Gio require a running GNOME session. Replace only those boundaries;
// execute the extension's real lifecycle and asynchronous completion handlers.
function harness({lateIndicator = false} = {}) {
    const jobs = [];
    const handlers = new Map();
    const input = {
        _stream: {}, _showInput: true, visible: true,
        _control: {get_sources: () => [{state: 1}]},
        _sync() { this.visible = this._showInput; },
        _maybeShowInput() { this._showInput = true; this._sync(); },
    };
    const original = input._maybeShowInput;
    Object.defineProperty(input, 'stream', {
        get() { return this._stream; },
        set(value) { this._stream = value; this._maybeShowInput(); },
    });
    const extensionSettings = {
        ...settings,
        connect(_signal, callback) { const id = handlers.size + 1; handlers.set(id, callback); return id; },
        disconnect(id) { handlers.delete(id); },
    };
    class Extension { getSettings() { return extensionSettings; } }
    class InjectionManager {
        constructor() { this.originals = []; }
        overrideMethod(target, name, createOverride) {
            this.originals.push([target, name, target[name]]);
            target[name] = createOverride(target[name]);
        }
        clear() {
            for (const [target, name, originalMethod] of this.originals.reverse())
                target[name] = originalMethod;
            this.originals = [];
        }
    }
    class InputIndicator {
        constructor() {
            this._input = input;
            this._control = {get_default_source: () => ({})};
            this._readInput();
        }
        _readInput() { this._input.stream = this._control.get_default_source(); }
    }
    const originalReadInput = InputIndicator.prototype._readInput;
    const quickSettings = lateIndicator ? {} : {_volumeInput: new InputIndicator()};
    class Cancellable { cancel() {} }
    const Gio = {
        Cancellable, SubprocessFlags: {STDOUT_PIPE: 1, STDERR_PIPE: 2},
        Subprocess: {new(argv) {
            assert.deepEqual(Array.from(argv).slice(1), ['--format=json', 'list', 'source-outputs']);
            const process = {
                successful: true, killed: false,
                communicate_utf8_async(_stdin, _cancel, callback) { this.callback = callback; },
                communicate_utf8_finish(result) {
                    if (result.error) throw result.error;
                    return [true, result.stdout, ''];
                },
                get_successful() { return this.successful; },
                force_exit() { this.killed = true; },
                finish(stdout, error) { this.callback(this, {stdout, error}); },
            };
            jobs.push(process);
            return process;
        }},
    };
    const context = vm.createContext({
        Extension, InjectionManager, Volume: {InputIndicator},
        Gio, Gvc: {MixerStreamState: {RUNNING: 1}}, shouldShowInput,
        Main: {panel: {statusArea: {quickSettings}}},
        console: {error() {}},
    });
    const source = readFileSync(new URL('./extension.js', import.meta.url), 'utf8')
        .replace(/^import .*;\n/gm, '')
        .replace('export default class', 'class');
    vm.runInContext(`${source}\nglobalThis.ExtensionClass = MicIndicatorVisibilityManagerExtension;`, context);
    const extension = new context.ExtensionClass();
    extension.enable();
    const createIndicator = () => {
        quickSettings._volumeInput = new InputIndicator();
    };
    return {extension, input, original, jobs, handlers, createIndicator,
        InputIndicator, originalReadInput, quickSettings};
}

test('a microphone indicator created after enable receives the filter', () => {
    const h = harness({lateIndicator: true});
    assert.equal(h.jobs.length, 0);
    h.createIndicator();
    h.jobs[0].finish(JSON.stringify([capture, reference]));
    assert.equal(h.input.visible, false);
    h.input._maybeShowInput();
    h.jobs[1].finish(JSON.stringify([capture, reference, {properties: {'node.name': 'recorder'}}]));
    assert.equal(h.input.visible, true);
    h.extension.disable();
    assert.equal(h.InputIndicator.prototype._readInput, h.originalReadInput);
});

test('disable before indicator creation leaves subsequent GNOME initialization alone', () => {
    const h = harness({lateIndicator: true});
    h.extension.disable();
    h.createIndicator();
    assert.equal(h.jobs.length, 0);
    assert.equal(h.input._maybeShowInput, h.original);
    assert.equal(h.input.visible, true);
    assert.equal(h.handlers.size, 0);
    assert.equal(h.InputIndicator.prototype._readInput, h.originalReadInput);
});

test('repeated GNOME input initialization does not attach the filter twice', () => {
    const h = harness({lateIndicator: true});
    h.createIndicator();
    h.jobs[0].finish(JSON.stringify([capture, reference]));
    h.quickSettings._volumeInput._readInput();
    assert.equal(h.jobs.length, 2);
    h.jobs[1].finish(JSON.stringify([capture, reference]));
    assert.equal(h.input.visible, false);
    assert.equal(h.jobs.length, 2);
    h.extension.disable();
});

test('JSON completes asynchronously and an application stream restores the indicator', () => {
    const h = harness();
    assert.equal(h.input.visible, true); // standard display until the query succeeds
    h.jobs[0].finish(JSON.stringify([capture, reference]));
    assert.equal(h.input.visible, false);
    h.input._maybeShowInput();
    h.jobs[1].finish(JSON.stringify([capture, reference, {properties: {'node.name': 'recorder'}}]));
    assert.equal(h.input.visible, true);
    h.extension.disable();
});
test('invalid JSON and command failures fall back to the standard indicator', () => {
    for (const result of ['not json', '{}', JSON.stringify([{}])]) {
        const h = harness();
        h.jobs[0].finish(JSON.stringify([capture, reference]));
        h.input._maybeShowInput();
        h.jobs[1].finish(result);
        assert.equal(h.input.visible, true);
        h.extension.disable();
    }
    const h = harness();
    h.jobs[0].successful = false;
    h.jobs[0].finish('[]');
    assert.equal(h.input.visible, true);
    h.extension.disable();
});
test('a stream change during a pending query does not apply stale hidden state', () => {
    const h = harness();
    h.input._maybeShowInput();
    h.jobs[0].finish(JSON.stringify([capture, reference]));
    assert.equal(h.input.visible, true);
    h.jobs[1].finish(JSON.stringify([capture, reference, {properties: {'node.name': 'recorder'}}]));
    assert.equal(h.input.visible, true);
    h.extension.disable();
});
test('disabling restores standard behavior and late results cannot hide the indicator', () => {
    const h = harness();
    h.extension.disable();
    assert.equal(h.input._maybeShowInput, h.original);
    assert.equal(h.handlers.size, 0);
    assert.equal(h.jobs[0].killed, true);
    h.jobs[0].finish(JSON.stringify([capture, reference]));
    assert.equal(h.input.visible, true);
});
test('an idle source retains the standard inactive indicator', () => {
    const h = harness();
    h.input._control.get_sources = () => [{state: 0}];
    h.jobs[0].finish(JSON.stringify([{properties: {'node.name': 'recorder'}}]));
    assert.equal(h.input.visible, false);
    h.extension.disable();
});

test('a settings change refreshes the indicator without reloading the extension', () => {
    const h = harness();
    h.jobs[0].finish(JSON.stringify([capture, reference]));
    assert.equal(h.input.visible, false);
    h.handlers.values().next().value();
    h.jobs[1].finish(JSON.stringify([{properties: {'node.name': 'recorder'}}]));
    assert.equal(h.input.visible, true);
    h.extension.disable();
});
test('reenabling ignores a completion from the previous instance', () => {
    const h = harness();
    h.extension.disable();
    h.extension.enable();
    h.jobs[0].finish(JSON.stringify([capture, reference]));
    assert.equal(h.input.visible, true);
    h.jobs[1].finish(JSON.stringify([capture, reference]));
    assert.equal(h.input.visible, false);
    h.extension.disable();
});
