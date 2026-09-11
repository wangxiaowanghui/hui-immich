<script lang="ts">
  import { afterNavigate } from '$app/navigation';
  import OnEvents from '$lib/components/OnEvents.svelte';
  import MapSettingsModal from '$lib/modals/MapSettingsModal.svelte';
  import { mapSettings } from '$lib/stores/preferences.store';
  import {
    gcj02ToWgs84,
    loadAmap,
    wgs84ToGcj02,
    type AmapApi,
    type AmapInstance,
    type AmapMarker,
    type MapCoordinates,
  } from '$lib/utils/amap';
  import { getAssetMediaUrl } from '$lib/utils';
  import { getMapMarkers, type MapMarkerResponseDto } from '@immich/sdk';
  import { Icon, modalManager, Theme, themeManager } from '@immich/ui';
  import { mdiCog, mdiCrosshairsGps, mdiMap, mdiMinus, mdiPlus } from '@mdi/js';
  import { isEqual, omit } from 'lodash-es';
  import { DateTime, Duration } from 'luxon';
  import { LngLat, type LngLatLike } from 'maplibre-gl';
  import { onDestroy, onMount, untrack } from 'svelte';
  import { t } from 'svelte-i18n';
  import type { SelectionBBox } from './types';

  interface Props {
    amapKey: string;
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
    onFailure: () => void;
  }

  let {
    amapKey,
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
    onFailure,
  }: Props = $props();

  let container: HTMLDivElement;
  let api: AmapApi | undefined;
  let map: AmapInstance | undefined;
  let renderedMarkers: AmapMarker[] = [];
  let clipMarker: AmapMarker | undefined;
  let abortController: AbortController;
  let fittedInitialBounds = false;
  const mapTheme = $derived($mapSettings.allowDarkMode ? themeManager.value : Theme.Light);

  export function addClipMapMarker(lng: number, lat: number) {
    if (!map || !api) {
      return;
    }
    const gcj02 = wgs84ToGcj02({ lng, lat });
    const position = new api.LngLat(gcj02.lng, gcj02.lat);
    if (clipMarker) {
      clipMarker.setPosition(position);
    } else {
      clipMarker = new api.Marker({ map, position, content: createPin() });
    }
    center = { lng, lat };
    map.setZoomAndCenter(zoom ?? 12, position);
  }

  const getFileCreatedDates = () => {
    const { relativeDate, dateAfter, dateBefore } = $mapSettings;
    if (relativeDate) {
      const duration = Duration.fromISO(relativeDate);
      return { fileCreatedAfter: duration.isValid ? DateTime.now().minus(duration).toUTC().toISO() : undefined };
    }
    return { fileCreatedAfter: dateAfter, fileCreatedBefore: dateBefore };
  };

  const loadMapMarkers = async () => {
    abortController?.abort();
    abortController = new AbortController();
    const { includeArchived, onlyFavorites, withPartners, withSharedAlbums } = $mapSettings;
    const { fileCreatedAfter, fileCreatedBefore } = getFileCreatedDates();
    return getMapMarkers(
      {
        isArchived: includeArchived || undefined,
        isFavorite: onlyFavorites || undefined,
        fileCreatedAfter,
        fileCreatedBefore,
        withPartners: withPartners || undefined,
        withSharedAlbums: withSharedAlbums || undefined,
      },
      { signal: abortController.signal },
    );
  };

  const handleSettingsClick = async () => {
    const settings = await modalManager.show(MapSettingsModal);
    if (!settings) {
      return;
    }
    const shouldUpdate = !isEqual(omit(settings, 'allowDarkMode'), omit($mapSettings, 'allowDarkMode'));
    $mapSettings = settings;
    if (shouldUpdate) {
      mapMarkers = await loadMapMarkers();
    }
  };

  onMount(async () => {
    try {
      api = await loadAmap(amapKey, `${location.origin}/_AMapService`);
      const initial = wgs84ToGcj02(center ? LngLat.convert(center) : { lng: 0, lat: 0 });
      map = new api.Map(container, {
        center: [initial.lng, initial.lat],
        zoom: Math.max(zoom ?? 3, 3),
        mapStyle: mapTheme === Theme.Dark ? 'amap://styles/dark' : 'amap://styles/normal',
        lang: 'zh_cn',
        viewMode: '3D',
        rotateEnable: false,
        pitchEnable: false,
        zooms: [3, 18],
      });
      map.on('click', handleMapClick);
      map.on('moveend', handleMoveEnd);
      map.on('zoomend', handleMoveEnd);
      map.on('error', onFailure);
      if (!mapMarkers) {
        mapMarkers = await loadMapMarkers();
      }
      fitInitialBounds();
      renderMarkers();
    } catch {
      onFailure();
    }
  });

  onDestroy(() => {
    abortController?.abort();
    removeRenderedMarkers();
    clipMarker?.setMap(null);
    map?.destroy();
  });

  afterNavigate(() => map?.resize());

  $effect(() => {
    mapMarkers;
    untrack(() => {
      fitInitialBounds();
      renderMarkers();
    });
  });

  $effect(() => {
    if (!map || !api || !center || zoom === undefined) {
      return;
    }
    const converted = wgs84ToGcj02(LngLat.convert(center));
    untrack(() => map?.setZoomAndCenter(zoom, new api!.LngLat(converted.lng, converted.lat)));
  });

  $effect(() => {
    map?.setMapStyle(mapTheme === Theme.Dark ? 'amap://styles/dark' : 'amap://styles/normal');
  });

  const fitInitialBounds = () => {
    if (!map || !api || fittedInitialBounds || !autoFitBounds || center || zoom !== undefined || !mapMarkers?.length) {
      return;
    }
    const converted = mapMarkers.map(({ lon, lat }) => wgs84ToGcj02({ lng: lon, lat }));
    const west = Math.min(...converted.map(({ lng }) => lng));
    const east = Math.max(...converted.map(({ lng }) => lng));
    const south = Math.min(...converted.map(({ lat }) => lat));
    const north = Math.max(...converted.map(({ lat }) => lat));
    map.setBounds(
      new api.Bounds(new api.LngLat(west, south), new api.LngLat(east, north)),
      false,
      [50, 50, 50, 50],
      15,
    );
    fittedInitialBounds = true;
  };

  const handleMoveEnd = () => {
    if (!map) {
      return;
    }
    const mapCenter = map.getCenter();
    center = gcj02ToWgs84({ lng: mapCenter.getLng(), lat: mapCenter.getLat() });
    if (hash) {
      history.replaceState(null, '', `#${map.getZoom().toFixed(2)}/${center.lat.toFixed(5)}/${center.lng.toFixed(5)}`);
    }
    renderMarkers();
  };

  const handleMapClick = (event: { lnglat: { getLng(): number; getLat(): number } }) => {
    if (!clickable || !api || !map) {
      return;
    }
    const wgs84 = gcj02ToWgs84({ lng: event.lnglat.getLng(), lat: event.lnglat.getLat() });
    onClickPoint(wgs84);
    addClipMapMarker(wgs84.lng, wgs84.lat);
  };

  const renderMarkers = () => {
    if (!map || !api || !mapMarkers) {
      return;
    }
    removeRenderedMarkers();
    const bounds = map.getBounds();
    const visible = mapMarkers
      .map((marker) => ({ marker, gcj02: wgs84ToGcj02({ lng: marker.lon, lat: marker.lat }) }))
      .filter(({ gcj02 }) => bounds.contains(new api!.LngLat(gcj02.lng, gcj02.lat)));
    const groups = new Map<string, typeof visible>();
    for (const point of visible) {
      const pixel = map.lngLatToContainer(new api.LngLat(point.gcj02.lng, point.gcj02.lat));
      const key = `${Math.floor(pixel.getX() / 52)}:${Math.floor(pixel.getY() / 52)}`;
      const group = groups.get(key) ?? [];
      group.push(point);
      groups.set(key, group);
    }

    for (const group of groups.values()) {
      const lng = group.reduce((sum, point) => sum + point.gcj02.lng, 0) / group.length;
      const lat = group.reduce((sum, point) => sum + point.gcj02.lat, 0) / group.length;
      const content = group.length === 1 ? createSingleMarker(group[0].marker) : createClusterMarker(group.length);
      const rendered = new api.Marker({
        map,
        position: new api.LngLat(lng, lat),
        anchor: group.length === 1 && useLocationPin ? 'bottom-center' : 'center',
        content,
        zIndex: 120,
      });
      rendered.on('click', () => handleMarkerClick(group));
      renderedMarkers.push(rendered);
    }
  };

  const removeRenderedMarkers = () => {
    for (const marker of renderedMarkers) {
      marker.setMap(null);
    }
    renderedMarkers = [];
  };

  const handleMarkerClick = (group: { marker: MapMarkerResponseDto; gcj02: MapCoordinates }[]) => {
    const ids = group.map(({ marker }) => marker.id);
    if (group.length > 1 && onClusterSelect) {
      const longitudes = group.map(({ marker }) => marker.lon);
      const latitudes = group.map(({ marker }) => marker.lat);
      onClusterSelect(ids, {
        west: Math.min(...longitudes),
        south: Math.min(...latitudes),
        east: Math.max(...longitudes),
        north: Math.max(...latitudes),
      });
      return;
    }
    if (group.length === 1 && popup) {
      showCoordinatePopup(group[0].marker);
      return;
    }
    onSelect(ids);
  };

  const showCoordinatePopup = (marker: MapMarkerResponseDto) => {
    if (!api || !map) {
      return;
    }
    const content = document.createElement('div');
    content.style.cssText = 'display:flex;flex-direction:column;gap:6px;align-items:center;padding:4px;color:#111';
    const coordinates = document.createElement('strong');
    coordinates.textContent = `${marker.lat.toPrecision(6)}, ${marker.lon.toPrecision(6)}`;
    const link = document.createElement('a');
    link.textContent = 'OpenStreetMap';
    link.href = `https://www.openstreetmap.org/?mlat=${marker.lat}&mlon=${marker.lon}#map=15/${marker.lat}/${marker.lon}`;
    link.target = '_blank';
    link.rel = 'noopener';
    link.style.color = '#3f51b5';
    content.append(coordinates, link);
    const converted = wgs84ToGcj02({ lng: marker.lon, lat: marker.lat });
    new api.InfoWindow({ content, offset: [0, -24] }).open(map, new api.LngLat(converted.lng, converted.lat));
  };

  const createSingleMarker = (marker: MapMarkerResponseDto) => {
    if (useLocationPin) {
      return createPin();
    }
    const button = document.createElement('button');
    button.type = 'button';
    button.title = marker.city && marker.country ? `${marker.city}, ${marker.country}` : 'Immich photo';
    button.style.cssText =
      'width:48px;height:48px;border:2px solid #3f51b5;border-radius:50%;padding:0;overflow:hidden;background:#3f51b5;box-shadow:0 3px 10px #0005;cursor:pointer';
    const image = document.createElement('img');
    image.src = getAssetMediaUrl({ id: marker.id });
    image.alt = button.title;
    image.style.cssText = 'width:100%;height:100%;object-fit:cover';
    button.append(image);
    return button;
  };

  const createClusterMarker = (count: number) => {
    const button = document.createElement('button');
    button.type = 'button';
    button.textContent = count.toLocaleString();
    button.style.cssText =
      'display:flex;align-items:center;justify-content:center;width:40px;height:40px;border:2px solid white;border-radius:50%;background:#3f51b5;color:white;font:700 14px monospace;box-shadow:0 3px 10px #0005;cursor:pointer';
    return button;
  };

  const createPin = () => {
    const pin = document.createElement('div');
    pin.style.cssText =
      'width:24px;height:24px;border:3px solid white;border-radius:50% 50% 50% 0;background:#3f51b5;box-shadow:0 2px 8px #0006;transform:rotate(-45deg)';
    return pin;
  };

  const zoomToBrowserLocation = () => {
    navigator.geolocation?.getCurrentPosition(({ coords }) => {
      if (!api || !map) {
        return;
      }
      const converted = wgs84ToGcj02({ lng: coords.longitude, lat: coords.latitude });
      map.setZoomAndCenter(14, new api.LngLat(converted.lng, converted.lat));
    });
  };

  const onAssetsChanged = async () => (mapMarkers = await loadMapMarkers());
</script>

<OnEvents onAssetsDelete={onAssetsChanged} onAssetsArchive={onAssetsChanged} onAssetsUnarchive={onAssetsChanged} />

<div class="relative size-full overflow-hidden {rounded ? 'rounded-2xl' : 'rounded-none'}">
  <div bind:this={container} class="size-full" aria-label={$t('map')} role="application"></div>

  {#if showSimpleControls}
    <div class="absolute top-3 left-3 z-10 flex flex-col gap-1">
      <button class="amap-control" type="button" aria-label="Zoom in" onclick={() => map?.zoomIn()}
        ><Icon icon={mdiPlus} /></button
      >
      <button class="amap-control" type="button" aria-label="Zoom out" onclick={() => map?.zoomOut()}
        ><Icon icon={mdiMinus} /></button
      >
      {#if !simplified}
        <button class="amap-control" type="button" aria-label="Current location" onclick={zoomToBrowserLocation}
          ><Icon icon={mdiCrosshairsGps} /></button
        >
      {/if}
    </div>
  {/if}

  <div class="absolute top-3 right-3 z-10 flex gap-1">
    {#if showSettings}
      <button class="amap-control" type="button" aria-label={$t('map_settings')} onclick={handleSettingsClick}
        ><Icon icon={mdiCog} /></button
      >
    {/if}
    {#if onOpenInMapView && showSimpleControls}
      <button class="amap-control" type="button" aria-label={$t('open_in_map_view')} onclick={() => onOpenInMapView?.()}
        ><Icon icon={mdiMap} /></button
      >
    {/if}
  </div>
</div>

<style>
  .amap-control {
    display: flex;
    width: 34px;
    height: 34px;
    align-items: center;
    justify-content: center;
    border: 0;
    border-radius: 4px;
    background: white;
    color: #263238;
    box-shadow: 0 1px 5px #0005;
    cursor: pointer;
  }
</style>
