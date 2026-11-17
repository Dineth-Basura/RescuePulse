"use strict";
// RescuePulse 2.0 — Live Weather Intelligence
// Data source: Open-Meteo API (free for noncommercial prototype use).
// Operational context only — not an official government disaster warning.
window.RescueWeather = {
  async current(latitude, longitude) {
    if (typeof latitude !== 'number' || typeof longitude !== 'number' || !Number.isFinite(latitude) || !Number.isFinite(longitude)) {
      throw new Error('Valid coordinates required for weather check.');
    }
    const url = new URL('https://api.open-meteo.com/v1/forecast');
    url.searchParams.set('latitude', latitude.toFixed(4));
    url.searchParams.set('longitude', longitude.toFixed(4));
    url.searchParams.set('current', 'temperature_2m,relative_humidity_2m,precipitation,rain,wind_speed_10m,wind_gusts_10m');
    url.searchParams.set('daily', 'precipitation_sum,wind_speed_10m_max,temperature_2m_max,temperature_2m_min');
    url.searchParams.set('timezone', 'Asia/Colombo');
    url.searchParams.set('forecast_days', '2');

    const response = await fetch(url, {signal: AbortSignal.timeout(12000)});
    if (!response.ok) {
      throw new Error(`Open-Meteo weather service unavailable (${response.status})`);
    }
    const data = await response.json();
    return {
      current: data.current,
      units: data.current_units,
      daily: data.daily,
      dailyUnits: data.daily_units,
      source: 'Open-Meteo (Asia/Colombo timezone)',
      retrievedAt: new Date().toLocaleTimeString('en-LK', {timeZone: 'Asia/Colombo', hour: '2-digit', minute: '2-digit', second: '2-digit'})
    };
  },

  formatSummary(result) {
    const c = result.current;
    const u = result.units || {};
    const d = result.daily;
    const todayPrecip = d?.precipitation_sum?.[0] !== undefined ? `${d.precipitation_sum[0]} mm` : 'N/A';
    const maxWind = d?.wind_speed_10m_max?.[0] !== undefined ? `${d.wind_speed_10m_max[0]} km/h` : 'N/A';

    return {
      text: `Open-Meteo (${result.retrievedAt}): ${c.temperature_2m}${u.temperature_2m || '°C'} · ${c.relative_humidity_2m}% humidity · ${c.precipitation} mm precip (24h est: ${todayPrecip}) · Wind ${c.wind_speed_10m} km/h (gusts ${c.wind_gusts_10m || 0} km/h, max ${maxWind})`,
      disclaimer: 'Operational context only. Distinguish observed weather from heuristic risk scores. Not official government disaster instructions.'
    };
  }
};
