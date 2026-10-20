import ballerina/http;
import ballerina/log;

type PredictRequest record {
    float rainMm;
    float windKph;
    float tempC;
    float humidityPct;
    float soilSatPct;
};

type PredictResponse record {
    float riskScore;
};

type TrainRecord record {
    float rainMm;
    float windKph;
    float tempC;
    float humidityPct;
    float soilSatPct;
};

public class RiskModel {
    public float wRain = 0.35;
    public float wWind = 0.25;
    public float wTemp = 0.15;
    public float wHumidity = 0.10;
    public float wSoil = 0.15;
    public float bias = 0.0;

    function predict(float rainMm, float windKph, float tempC, float humidityPct, float soilSatPct) returns float {
        float score = (rainMm / 200.0) * self.wRain
            + (windKph / 120.0) * self.wWind
            + ((40.0 - tempC) / 40.0) * self.wTemp
            + (humidityPct / 100.0) * self.wHumidity
            + (soilSatPct / 100.0) * self.wSoil + self.bias;
        if score < 0.0 {
            return 0.0;
        }
        if score > 1.0 {
            return 1.0;
        }
        return score;
    }
}

final RiskModel MODEL = new;

service /ai on httpListener {
    resource function get health() returns json {
        return {status: "ai-service:ok"};
    }

    resource function post predict(@http:Payload PredictRequest req) returns PredictResponse|http:BadRequest {
        if !validWeather(req.rainMm, req.windKph, req.tempC, req.humidityPct, req.soilSatPct) {
            return <http:BadRequest>{body: {message: "Weather values outside supported ranges"}};
        }
        float risk = MODEL.predict(req.rainMm, req.windKph, req.tempC, req.humidityPct, req.soilSatPct);
        log:printDebug("Predicted risk: " + risk.toString());
        return {riskScore: risk};
    }

    resource function post train() returns http:NotImplemented {
        return {body: {message: "Model training is not available. The risk index uses configured environmental weights."}};
    }
}

function validWeather(float rain, float wind, float temp, float humidity, float soil) returns boolean {
    return rain >= 0.0 && rain <= 1000.0 && wind >= 0.0 && wind <= 400.0 && temp >= -50.0 && temp <= 60.0 && humidity >= 0.0 && humidity <= 100.0 && soil >= 0.0 && soil <= 100.0;
}
