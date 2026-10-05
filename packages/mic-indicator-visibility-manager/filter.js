// Keep application recording visible while excluding only configured streams.
export function shouldShowInput(outputs, settings) {
    if (!Array.isArray(outputs) || outputs.some(output =>
        !output || !output.properties || typeof output.properties !== 'object' ||
        Array.isArray(output.properties)))
        throw new Error('Invalid source-output JSON');

    const skippedApps = settings.get_strv('skipped-apps');
    const ignoredProperties = settings.get_strv('ignored-properties');
    return outputs.some(output => {
        const properties = output.properties;
        if (!settings.get_boolean('show-virtual-sources') && properties['node.virtual'] === 'true')
            return false;
        if (skippedApps.includes(properties['application.id']))
            return false;
        return !ignoredProperties.some(property => {
            const colon = property.indexOf(':');
            return colon > 0 && properties[property.slice(0, colon)] === property.slice(colon + 1);
        });
    });
}
