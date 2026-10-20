import ballerina/http;
import ballerina/test;

@test:Config {}
function testValidatedResponseWorkflow() returns error? {
    http:Client c = check new ("http://localhost:8080");
    http:Response invalid = check c->post("/ai/predict", {rainMm: -1, windKph: 10, tempC: 30, humidityPct: 50, soilSatPct: 50});
    test:assertEquals(invalid.statusCode, 400);
    http:Response forbidden = check c->get("/admin/users", headers = {Authorization: "Bearer demo-token-admin"});
    test:assertEquals(forbidden.statusCode, 403);
    http:Response reserved = check c->post("/auth/signup", {username: "admin", password: "password123"});
    test:assertEquals(reserved.statusCode, 400);
    PredictResponse risk = check c->post("/ai/predict", {rainMm: 250, windKph: 90, tempC: 24, humidityPct: 95, soilSatPct: 95}, targetType = PredictResponse);
    test:assertTrue(risk.riskScore >= 0.65 && risk.riskScore <= 1.0);
    http:Response anonymous = check c->post("/incident/create", {location: "Colombo", description: "Test", severity: "LOW"});
    test:assertEquals(anonymous.statusCode, 401);
    AuthResponse login = check c->post("/auth/login", {username: "admin", password: "Test-only-password-2026"}, targetType = AuthResponse);
    string token = login.token ?: "";
    test:assertTrue(token.length() > 20);
    map<string> headers = {Authorization: "Bearer " + token};
    Incident incident = check c->post("/incident/create", {location: "Test district", description: "Automated workflow check", severity: "HIGH"}, headers = headers, targetType = Incident);
    test:assertTrue(incident.id.startsWith("inc-"));
    incident.status = "ACK";
    Incident acknowledged = check c->put("/incident/update/" + incident.id, incident, headers = headers, targetType = Incident);
    test:assertEquals(acknowledged.status, "ACK");
    incident = acknowledged;
    incident.status = "RESOLVED";
    Incident resolved = check c->put("/incident/update/" + incident.id, incident, headers = headers, targetType = Incident);
    test:assertEquals(resolved.status, "RESOLVED");
    http:Response removed = check c->delete("/incident/" + incident.id, headers = headers);
    test:assertEquals(removed.statusCode, 200);
    http:Response logout = check c->post("/auth/logout", {}, headers = headers);
    test:assertEquals(logout.statusCode, 200);
    http:Response expired = check c->get("/auth/me", headers = headers);
    test:assertEquals(expired.statusCode, 401);
}
