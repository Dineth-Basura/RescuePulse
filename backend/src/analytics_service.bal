import ballerina/http;
import ballerina/log;

type SummaryRequest record {
    WeatherPoint[] points;
};

type WeatherPoint record {
    float rainMm;
    float windKph;
    float tempC;
    float humidityPct;
    float soilSatPct;
};

type SummaryResponse record {
    int count;
    float avgRainMm;
    float avgWindKph;
    float avgTempC;
    float avgHumidityPct;
    float avgSoilSatPct;
    float riskEstAvg;
};

service /analytics on httpListener {
    resource function get health() returns json {
        return {status: "analytics-service:ok"};
    }

    resource function post summarize(@http:Payload SummaryRequest req) returns SummaryResponse|json|http:BadRequest {
        WeatherPoint[] pts = req.points;
        if pts.length() == 0 {
            return {message: "no points"};
        }
        float sumRain = 0.0;
        float sumWind = 0.0;
        float sumTemp = 0.0;
        float sumHum = 0.0;
        float sumSoil = 0.0;
        float sumRisk = 0.0;
        foreach var p in pts {
            if !validWeather(p.rainMm, p.windKph, p.tempC, p.humidityPct, p.soilSatPct) {
                return <http:BadRequest>{body: {message: "Invalid weather point"}};
            }
            sumRain += p.rainMm;
            sumWind += p.windKph;
            sumTemp += p.tempC;
            sumHum += p.humidityPct;
            sumSoil += p.soilSatPct;
            float risk = (p.rainMm / 200.0) * 0.35 + (p.windKph / 120.0) * 0.25 + ((40.0 - p.tempC) / 40.0) * 0.15 + (p.humidityPct / 100.0) * 0.10 + (p.soilSatPct / 100.0) * 0.15;
            if risk < 0.0 {
                risk = 0.0;
            }
            if risk > 1.0 {
                risk = 1.0;
            }
            sumRisk += risk;
        }
        int n = pts.length();
        SummaryResponse out = {
            count: n,
            avgRainMm: sumRain / n,
            avgWindKph: sumWind / n,
            avgTempC: sumTemp / n,
            avgHumidityPct: sumHum / n,
            avgSoilSatPct: sumSoil / n,
            riskEstAvg: sumRisk / n
        };
        log:printDebug("analytics summarized " + n.toString() + " points");
        return out;
    }
}

