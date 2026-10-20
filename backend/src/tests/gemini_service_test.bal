import ballerina/test;
import ballerina/http;

@test:Config {}
function testGeminiStructuredBriefParsing() returns error? {
    json payload = {candidates: [{finishReason: "STOP", content: {parts: [
        {thought: true, text: "Internal reasoning is not displayed"},
        {text: "{\"summary\":\"Access road reported flooded.\",\"suggestedActions\":[\"Confirm access with the assigned responder.\"],\"missingInformation\":[\"Current water depth\"],\"handover\":\"Check road access before assigning transport.\"}"}
    ]}}]};
    AiBrief brief = check decodeGeminiBrief(payload);
    test:assertEquals(brief.summary, "Access road reported flooded.");
    test:assertEquals(brief.suggestedActions.length(), 1);
    test:assertTrue(brief.missingInformation[0] == "Current water depth");
}

@test:Config {}
function testGeminiRejectsBlockedAndMalformedOutput() {
    test:assertTrue(decodeGeminiBrief({candidates: []}) is error);
    test:assertTrue(decodeGeminiBrief({candidates: [{finishReason: "SAFETY", content: {parts: []}}]}) is error);
    test:assertTrue(decodeGeminiBrief({candidates: [{finishReason: "MAX_TOKENS", content: {parts: [{text: "partial"}]}}]}) is error);
    test:assertTrue(decodeGeminiBrief({candidates: [{finishReason: "STOP", content: {parts: [{text: "not JSON"}]}}]}) is error);
    test:assertFalse(validAiBrief({summary: "", suggestedActions: [], missingInformation: [], handover: "Draft"}));
}

@test:Config {}
function testGeminiEndpointsRequireAuthentication() returns error? {
    http:Client c = check new ("http://localhost:8080");
    http:Response status = check c->get("/assistant/status");
    test:assertEquals(status.statusCode, 401);
    http:Response brief = check c->post("/assistant/incidents/unknown/brief", {});
    test:assertEquals(brief.statusCode, 401);
    // The test configuration deliberately disables external provider calls.
    test:assertEquals(geminiApiKey, "");
}
