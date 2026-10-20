import ballerina/http;
import ballerina/test;

type StoreResponse record {
    string status;
};

@test:Config {}
function testIngestAndFetch() returns error? {
    http:Client c = check new ("http://localhost:8080");
    AuthResponse login = check c->post("/auth/login", {username: "admin", password: "Test-only-password-2026"}, targetType = AuthResponse);
    map<string> headers = {Authorization: "Bearer " + (login.token ?: "")};
    StoreResponse resp = check c->post("/data/ingest", {rainMm: 10.0, windKph: 5.0, tempC: 28.0, humidityPct: 55.0, soilSatPct: 40.0, location: "LOC1", timestamp: "2024-09-01T00:00:00Z"}, headers = headers, targetType = StoreResponse);
    test:assertEquals(resp.status, "stored");
    json list = check c->get("/data/latest/LOC1", headers = headers, targetType = json);
    test:assertTrue(list is json[]);
}

