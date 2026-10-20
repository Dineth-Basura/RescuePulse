import ballerina/http;
import ballerina/test;

@test:Config {}
function testEvaluateBelowThreshold() returns error? {
    http:Client c = check new ("http://localhost:8080");
    AlertResponse resp = check c->post("/alert/evaluate", {riskScore: 0.2, channel: "console", target: "demo"}, targetType = AlertResponse);
    test:assertEquals(resp.status, "ok");
}

