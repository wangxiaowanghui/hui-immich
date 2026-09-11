export interface MapCoordinates {
  lng: number;
  lat: number;
}

export interface AmapLngLat {
  getLng(): number;
  getLat(): number;
}

export interface AmapPixel {
  getX(): number;
  getY(): number;
}

export interface AmapBounds {
  contains(position: AmapLngLat): boolean;
}

export interface AmapEvent {
  lnglat: AmapLngLat;
}

export interface AmapMarker {
  on(event: string, listener: () => void): void;
  setMap(map: AmapInstance | null): void;
  setPosition(position: AmapLngLat): void;
  getPosition(): AmapLngLat;
}

export interface AmapInfoWindow {
  open(map: AmapInstance, position: AmapLngLat): void;
}

export interface AmapInstance {
  on(event: string, listener: (event: AmapEvent) => void): void;
  destroy(): void;
  resize(): void;
  getBounds(): AmapBounds;
  getCenter(): AmapLngLat;
  getZoom(): number;
  lngLatToContainer(position: AmapLngLat): AmapPixel;
  setBounds(bounds: AmapBounds, immediately?: boolean, avoid?: number[], maxZoom?: number): void;
  setMapStyle(style: string): void;
  setZoomAndCenter(zoom: number, center: AmapLngLat, immediately?: boolean): void;
  zoomIn(): void;
  zoomOut(): void;
}

export interface AmapApi {
  Map: new (container: HTMLElement, options: Record<string, unknown>) => AmapInstance;
  Marker: new (options: Record<string, unknown>) => AmapMarker;
  InfoWindow: new (options: Record<string, unknown>) => AmapInfoWindow;
  LngLat: new (longitude: number, latitude: number) => AmapLngLat;
  Bounds: new (southwest: AmapLngLat, northeast: AmapLngLat) => AmapBounds;
}

declare global {
  interface Window {
    AMap?: AmapApi;
    _AMapSecurityConfig?: { serviceHost: string };
  }
}

let loader: Promise<AmapApi> | undefined;

export const loadAmap = (key: string, serviceHost: string): Promise<AmapApi> => {
  if (window.AMap) {
    return Promise.resolve(window.AMap);
  }
  if (loader) {
    return loader;
  }

  window._AMapSecurityConfig = { serviceHost };
  loader = new Promise<AmapApi>((resolve, reject) => {
    const script = document.createElement('script');
    const timeout = window.setTimeout(() => reject(new Error('AMap JavaScript API load timed out')), 15_000);
    script.src = `https://webapi.amap.com/maps?v=2.0&key=${encodeURIComponent(key)}`;
    script.async = true;
    script.addEventListener('load', () => {
      window.clearTimeout(timeout);
      if (window.AMap) {
        resolve(window.AMap);
      } else {
        reject(new Error('AMap JavaScript API did not initialize'));
      }
    });
    script.addEventListener('error', () => {
      window.clearTimeout(timeout);
      reject(new Error('AMap JavaScript API failed to load'));
    });
    document.head.append(script);
  }).catch((error: unknown) => {
    loader = undefined;
    throw error;
  });
  return loader;
};

export const wgs84ToGcj02 = ({ lng, lat }: MapCoordinates): MapCoordinates => {
  if (outsideChina(lat, lng)) {
    return { lng, lat };
  }
  const [latitudeDelta, longitudeDelta] = coordinateDelta(lat, lng);
  return { lng: lng + longitudeDelta, lat: lat + latitudeDelta };
};

export const gcj02ToWgs84 = ({ lng, lat }: MapCoordinates): MapCoordinates => {
  if (outsideChina(lat, lng)) {
    return { lng, lat };
  }
  let estimate = { lng, lat };
  for (let index = 0; index < 3; index++) {
    const converted = wgs84ToGcj02(estimate);
    estimate = {
      lng: estimate.lng - (converted.lng - lng),
      lat: estimate.lat - (converted.lat - lat),
    };
  }
  return estimate;
};

const outsideChina = (latitude: number, longitude: number) =>
  longitude < 72.004 || longitude > 137.8347 || latitude < 0.8293 || latitude > 55.8271;

const coordinateDelta = (latitude: number, longitude: number): [number, number] => {
  const a = 6_378_245;
  const ee = 0.006_693_421_622_965_943;
  let latitudeDelta = transformLatitude(longitude - 105, latitude - 35);
  let longitudeDelta = transformLongitude(longitude - 105, latitude - 35);
  const radianLatitude = (latitude / 180) * Math.PI;
  let magic = Math.sin(radianLatitude);
  magic = 1 - ee * magic * magic;
  const sqrtMagic = Math.sqrt(magic);
  latitudeDelta = (latitudeDelta * 180) / (((a * (1 - ee)) / (magic * sqrtMagic)) * Math.PI);
  longitudeDelta = (longitudeDelta * 180) / ((a / sqrtMagic) * Math.cos(radianLatitude) * Math.PI);
  return [latitudeDelta, longitudeDelta];
};

const transformLatitude = (x: number, y: number) => {
  let result = -100 + 2 * x + 3 * y + 0.2 * y * y + 0.1 * x * y + 0.2 * Math.sqrt(Math.abs(x));
  result += ((20 * Math.sin(6 * x * Math.PI) + 20 * Math.sin(2 * x * Math.PI)) * 2) / 3;
  result += ((20 * Math.sin(y * Math.PI) + 40 * Math.sin((y / 3) * Math.PI)) * 2) / 3;
  result += ((160 * Math.sin((y / 12) * Math.PI) + 320 * Math.sin((y * Math.PI) / 30)) * 2) / 3;
  return result;
};

const transformLongitude = (x: number, y: number) => {
  let result = 300 + x + 2 * y + 0.1 * x * x + 0.1 * x * y + 0.1 * Math.sqrt(Math.abs(x));
  result += ((20 * Math.sin(6 * x * Math.PI) + 20 * Math.sin(2 * x * Math.PI)) * 2) / 3;
  result += ((20 * Math.sin(x * Math.PI) + 40 * Math.sin((x / 3) * Math.PI)) * 2) / 3;
  result += ((150 * Math.sin((x / 12) * Math.PI) + 300 * Math.sin((x / 30) * Math.PI)) * 2) / 3;
  return result;
};
