import {Extension, InjectionManager} from 'resource:///org/gnome/shell/extensions/extension.js';
import * as Main from 'resource:///org/gnome/shell/ui/main.js';
import * as Volume from 'resource:///org/gnome/shell/ui/status/volume.js';
import Gio from 'gi://Gio';
import Gvc from 'gi://Gvc';
import {shouldShowInput} from './filter.js';

// Adapted from the pinned upstream extension; see the package definition and
// docs/architecture/audio-echo-cancel.md for provenance and removal conditions.
export default class MicIndicatorVisibilityManagerExtension extends Extension {
    enable() {
        this._settings = null;
        this._settingsSignals = [];
        this._input = null;
        this._original = null;
        this._enabled = true;
        this._dirty = false;
        this._process = null;
        this._cancellable = null;
        this._injectionManager = null;
        this._settings = this.getSettings();
        this._injectionManager = new InjectionManager();
        // Quick Settings initializes asynchronously; attach when GNOME reads input.
        // See docs/architecture/audio-echo-cancel.md for the GNOME 50.4 ordering.
        const extension = this;
        this._injectionManager.overrideMethod(Volume.InputIndicator.prototype, '_readInput',
            original => function (...args) {
                const result = original.apply(this, args);
                extension._attach(this._input);
                return result;
            });
        this._settingsSignals = ['show-virtual-sources', 'skipped-apps', 'ignored-properties']
            .map(key => this._settings.connect(`changed::${key}`, () => this._refresh()));
        this._attach(Main.panel.statusArea.quickSettings?._volumeInput?._input);
    }

    _attach(input) {
        if (!this._enabled || !input || this._input === input)
            return;
        if (this._input)
            this._detach();
        this._input = input;
        this._original = input._maybeShowInput;
        input._maybeShowInput = () => this._refresh();
        this._refresh();
    }

    _detach() {
        this._cancellable?.cancel();
        this._process?.force_exit();
        this._process = null;
        this._cancellable = null;
        if (this._input && this._original) {
            this._input._maybeShowInput = this._original;
            this._original.call(this._input);
        }
        this._input = null;
        this._original = null;
    }

    _refresh() {
        if (!this._enabled || !this._input)
            return;

        // Until a successful query, retain GNOME's standard indication.
        this._original.call(this._input);
        if (this._process) {
            this._dirty = true;
            return;
        }
        if (!this._input._stream)
            return;

        this._dirty = false;
        this._cancellable = new Gio.Cancellable();
        const input = this._input;
        try {
            const process = Gio.Subprocess.new(
                ['@pactl@', '--format=json', 'list', 'source-outputs'],
                Gio.SubprocessFlags.STDOUT_PIPE | Gio.SubprocessFlags.STDERR_PIPE);
            this._process = process;
            process.communicate_utf8_async(null, this._cancellable, (source, result) => {
                // A disabled or re-enabled extension must ignore old completions.
                if (!this._enabled || this._process !== source)
                    return;
                try {
                    const [ok, stdout] = source.communicate_utf8_finish(result);
                    if (!ok || !source.get_successful())
                        throw new Error('pactl source-output query failed');
                    const showInput = shouldShowInput(JSON.parse(stdout), this._settings);
                    if (!this._dirty) {
                        input._showInput = input._stream !== null && showInput &&
                            input._control.get_sources().some(
                                node => node.state === Gvc.MixerStreamState.RUNNING);
                        input._sync();
                    }
                } catch (error) {
                    this._original.call(input);
                    console.error('Mic indicator query failed; using GNOME detection', error);
                } finally {
                    this._process = null;
                    this._cancellable = null;
                    if (this._dirty)
                        this._refresh();
                }
            });
        } catch (error) {
            this._process?.force_exit();
            this._process = null;
            this._cancellable = null;
            this._original.call(input);
            console.error('Mic indicator query failed; using GNOME detection', error);
        }
    }

    disable() {
        this._enabled = false;
        this._injectionManager?.clear();
        this._injectionManager = null;
        for (const signal of this._settingsSignals ?? [])
            this._settings.disconnect(signal);
        this._settingsSignals = [];
        this._detach();
        this._settings = null;
    }
}
