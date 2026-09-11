import { describe, expect, it } from 'vitest';
import { gcj02ToWgs84, wgs84ToGcj02 } from './amap';

describe('AMap coordinate conversion', () => {
  it('converts mainland WGS-84 coordinates and round trips', () => {
    const wgs84 = { lng: 116.39747, lat: 39.908823 };

    const gcj02 = wgs84ToGcj02(wgs84);
    const roundTrip = gcj02ToWgs84(gcj02);

    expect(gcj02.lng).toBeGreaterThan(wgs84.lng);
    expect(gcj02.lat).toBeGreaterThan(wgs84.lat);
    expect(roundTrip.lng).toBeCloseTo(wgs84.lng, 6);
    expect(roundTrip.lat).toBeCloseTo(wgs84.lat, 6);
  });

  it('leaves coordinates outside mainland China unchanged', () => {
    const london = { lng: -0.1278, lat: 51.5074 };

    expect(wgs84ToGcj02(london)).toEqual(london);
    expect(gcj02ToWgs84(london)).toEqual(london);
  });
});
