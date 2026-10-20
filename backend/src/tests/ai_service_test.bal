import ballerina/http;
import ballerina/test;

@test:Config {}
function testPredictionEndpoint() returns error? {
    http:Client c = check new ("http://localhost:8080");
    PredictResponse result = check c->post("/ai/predict", {rainMm: 50.0, windKph: 20.0, tempC: 30.0, humidityPct: 60.0, soilSatPct: 70.0}, targetType = PredictResponse);
    test:assertTrue(result.riskScore >= 0.0);
}

