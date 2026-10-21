import { installRegionReporter } from './hit-regions.js';

export function installDropRegions(options) {
  return installRegionReporter({ ...options, selector: '[data-drop]', attribute: 'data-drop', limit: 8, label: 'drop regions' });
}
