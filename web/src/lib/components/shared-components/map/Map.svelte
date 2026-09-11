<script lang="ts">
  import { serverConfigManager } from '$lib/managers/server-config-manager.svelte';
  import type { MapMarkerResponseDto, ServerConfigDto } from '@immich/sdk';
  import type { LngLatLike } from 'maplibre-gl';
  import { onMount } from 'svelte';
  import { t } from 'svelte-i18n';
  import AmapMap from './AmapMap.svelte';
  import MapLibreMap from './MapLibreMap.svelte';
  import type { SelectionBBox } from './types';

  interface Props {
    mapMarkers?: MapMarkerResponseDto[];
    showSettings?: boolean;
    zoom?: number;
    center?: LngLatLike;
    hash?: boolean;
    simplified?: boolean;
    clickable?: boolean;
    useLocationPin?: boolean;
    onOpenInMapView?: (() => Promise<void> | void) | undefined;
    onSelect?: (assetIds: string[]) => void;
    onClusterSelect?: (assetIds: string[], bbox: SelectionBBox) => void;
    onClickPoint?: ({ lat, lng }: { lat: number; lng: number }) => void;
    popup?: import('svelte').Snippet<[{ marker: MapMarkerResponseDto }]>;
    rounded?: boolean;
    showSimpleControls?: boolean;
    autoFitBounds?: boolean;
  }

  type AmapServerConfig = ServerConfigDto & { amapEnabled?: boolean; amapWebKey?: string };
  type MapComponent = { addClipMapMarker(lng: number, lat: number): void };

  let {
    mapMarkers = $bindable(),
    showSettings = true,
    zoom,
    center = $bindable(),
    hash = false,
    simplified = false,
    clickable = false,
    useLocationPin = false,
    onOpenInMapView,
    onSelect = () => {},
    onClusterSelect,
    onClickPoint = () => {},
    popup,
    rounded = false,
    showSimpleControls = true,
    autoFitBounds = true,
  }: Props = $props();

  let component = $state<MapComponent>();
  let consent = $state<'unknown' | 'accepted' | 'declined'>('unknown');
  let amapFailed = $state(false);
  const config = $derived(serverConfigManager.value as AmapServerConfig);
  const useAmap = $derived(config.amapEnabled === true && consent === 'accepted' && !amapFailed);
  const consentStorageKey = 'immich-amap-consent-v1';

  export function addClipMapMarker(lng: number, lat: number) {
    component?.addClipMapMarker(lng, lat);
  }

  onMount(() => {
    const saved = localStorage.getItem(consentStorageKey);
    consent = saved === 'accepted' ? 'accepted' : saved === 'declined' ? 'declined' : 'unknown';
  });

  const saveConsent = (decision: 'accepted' | 'declined') => {
    localStorage.setItem(consentStorageKey, decision);
    consent = decision;
  };
</script>

{#if useAmap && config.amapWebKey}
  <AmapMap
    bind:this={component}
    bind:mapMarkers
    bind:center
    amapKey={config.amapWebKey}
    {showSettings}
    {zoom}
    {hash}
    {simplified}
    {clickable}
    {useLocationPin}
    {onOpenInMapView}
    {onSelect}
    {onClusterSelect}
    {onClickPoint}
    {popup}
    {rounded}
    {showSimpleControls}
    {autoFitBounds}
    onFailure={() => (amapFailed = true)}
  />
{:else}
  <MapLibreMap
    bind:this={component}
    bind:mapMarkers
    bind:center
    {showSettings}
    {zoom}
    {hash}
    {simplified}
    {clickable}
    {useLocationPin}
    {onOpenInMapView}
    {onSelect}
    {onClusterSelect}
    {onClickPoint}
    {popup}
    {rounded}
    {showSimpleControls}
    {autoFitBounds}
  />
{/if}

{#if config.amapEnabled && consent === 'unknown'}
  <div class="fixed inset-0 z-[2000] flex items-center justify-center bg-black/55 p-4">
    <div class="w-full max-w-lg rounded-2xl bg-white p-6 text-gray-900 shadow-2xl dark:bg-gray-800 dark:text-white">
      <h2 class="mb-3 text-xl font-semibold">{$t('map_amap_privacy_title')}</h2>
      <p class="mb-5 text-sm leading-6">{$t('map_amap_privacy_content')}</p>
      <div class="flex flex-wrap items-center justify-end gap-2">
        <a
          class="mr-auto text-sm text-primary underline"
          href="https://lbs.amap.com/pages/privacy/"
          target="_blank"
          rel="noopener">{$t('map_amap_privacy_policy')}</a
        >
        <button class="rounded-lg px-4 py-2 text-sm" type="button" onclick={() => saveConsent('declined')}
          >{$t('map_amap_privacy_use_fallback')}</button
        >
        <button
          class="rounded-lg bg-primary px-4 py-2 text-sm font-medium text-white"
          type="button"
          onclick={() => saveConsent('accepted')}>{$t('map_amap_privacy_agree')}</button
        >
      </div>
    </div>
  </div>
{/if}
