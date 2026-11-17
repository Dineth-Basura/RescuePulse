import ballerina/http;
import ballerina/test;
import ballerina/uuid;

@test:Config {}
function testCommunityVerifiedRescueWorkflow() returns error? {
    http:Client c = check new ("http://localhost:8080");
    string suffix = uuid:createType4AsString().substring(0, 10);
    string community = "community-" + suffix;
    string responderName = "responder-" + suffix;
    AuthResponse adminLogin = check c->post("/auth/login", {username: "admin", password: "Test-only-password-2026"}, targetType = AuthResponse);
    map<string> adminHeaders = {Authorization: "Bearer " + (adminLogin.token ?: "")};
    AuthResponse signup = check c->post("/auth/signup", {username: community, password: "Community-demo-2026"}, targetType = AuthResponse);
    test:assertEquals(signup.status, "ok");
    AuthResponse communityLogin = check c->post("/auth/login", {username: community, password: "Community-demo-2026"}, targetType = AuthResponse);
    test:assertEquals(communityLogin.role ?: "", "citizen");
    map<string> communityHeaders = {Authorization: "Bearer " + (communityLogin.token ?: "")};
    http:Response createStaff = check c->post("/admin/users", {username: responderName, password: "Responder-demo-2026", role: "user"}, headers = adminHeaders);
    test:assertEquals(createStaff.statusCode, 201);
    AuthResponse responderLogin = check c->post("/auth/login", {username: responderName, password: "Responder-demo-2026"}, targetType = AuthResponse);
    map<string> responderHeaders = {Authorization: "Bearer " + (responderLogin.token ?: "")};
    Incident created = check c->post("/incident/create", {location: "Ratnapura", description: "Simulated water rising along road", category: "FLOOD", severity: "HIGH", latitude: 6.69, longitude: 80.39, affectedPeople: 4, assistanceRequested: true}, headers = communityHeaders, targetType = Incident);
    test:assertEquals(created.verificationStatus, "PENDING");
    test:assertEquals(created.reportedBy, community);
    http:Response citizenDirectory = check c->get("/operations/members", headers = communityHeaders);
    test:assertEquals(citizenDirectory.statusCode, 403);
    http:Response unauthorizedVerification = check c->post("/incident/" + created.id + "/verify", {decision: "VERIFIED", revision: created.revision}, headers = communityHeaders);
    test:assertEquals(unauthorizedVerification.statusCode, 403);
    Incident verified = check c->post("/incident/" + created.id + "/verify", {decision: "VERIFIED", revision: created.revision}, headers = adminHeaders, targetType = Incident);
    test:assertEquals(verified.verificationStatus, "VERIFIED");
    Incident assigned = check c->patch("/incident/" + created.id, {assignee: responderName, revision: verified.revision}, headers = adminHeaders, targetType = Incident);
    test:assertEquals(assigned.missionStatus, "ASSIGNED");
    http:Response wrongActor = check c->post("/incident/" + created.id + "/mission", {action: "ACCEPT", revision: assigned.revision}, headers = communityHeaders);
    test:assertEquals(wrongActor.statusCode, 403);
    Incident accepted = check c->post("/incident/" + created.id + "/mission", {action: "ACCEPT", revision: assigned.revision}, headers = responderHeaders, targetType = Incident);
    test:assertEquals(accepted.missionStatus, "ACCEPTED");
    Incident enRoute = check c->post("/incident/" + created.id + "/mission", {action: "EN_ROUTE", revision: accepted.revision}, headers = responderHeaders, targetType = Incident);
    Incident onScene = check c->post("/incident/" + created.id + "/mission", {action: "ON_SCENE", revision: enRoute.revision}, headers = responderHeaders, targetType = Incident);
    Incident completed = check c->post("/incident/" + created.id + "/mission", {action: "COMPLETE", revision: onScene.revision}, headers = responderHeaders, targetType = Incident);
    test:assertEquals(completed.missionStatus, "COMPLETED");
    test:assertEquals(completed.status, "RESOLVED");
    Incident sanitized = check c->get("/incident/" + created.id, headers = communityHeaders, targetType = Incident);
    test:assertEquals(sanitized.assignee, "");
    test:assertEquals(sanitized.history.length(), 0);
    http:Response removed = check c->delete("/incident/" + created.id, headers = adminHeaders);
    test:assertEquals(removed.statusCode, 200);
}

@test:Config {}
function testInvalidIncidentCoordinates() returns error? {
    http:Client c = check new ("http://localhost:8080");
    AuthResponse adminLogin = check c->post("/auth/login", {username: "admin", password: "Test-only-password-2026"}, targetType = AuthResponse);
    map<string> headers = {Authorization: "Bearer " + (adminLogin.token ?: "")};
    http:Response invalid = check c->post("/incident/create", {location: "Kandy", description: "Simulated coordinate validation", severity: "LOW", latitude: 91.0, longitude: 80.0}, headers = headers);
    test:assertEquals(invalid.statusCode, 400);
    http:Response partial = check c->post("/incident/create", {location: "Kandy", description: "Simulated partial coordinate", severity: "LOW", latitude: 7.0}, headers = headers);
    test:assertEquals(partial.statusCode, 400);
}

@test:Config {}
function testSecureAttachmentLifecycleAndValidation() returns error? {
    http:Client c = check new ("http://localhost:8080");
    // 1. Unauthenticated upload fails with 401
    http:Response unauth = check c->post("/incident/upload", {filename: "test.jpg", mimeType: "image/jpeg", base64Data: "SGVsbG8="});
    test:assertEquals(unauth.statusCode, 401);

    AuthResponse adminLogin = check c->post("/auth/login", {username: "admin", password: "Test-only-password-2026"}, targetType = AuthResponse);
    map<string> adminHeaders = {Authorization: "Bearer " + (adminLogin.token ?: "")};

    // 2. Invalid extension fails with 400
    http:Response badExt = check c->post("/incident/upload", {filename: "payload.exe", mimeType: "application/x-msdownload", base64Data: "AAAA"}, headers = adminHeaders);
    test:assertEquals(badExt.statusCode, 400);

    // 3. Invalid magic bytes fails with 400
    http:Response badMagic = check c->post("/incident/upload", {filename: "fake.jpg", mimeType: "image/jpeg", base64Data: "SGVsbG8gV29ybGQ="}, headers = adminHeaders);
    test:assertEquals(badMagic.statusCode, 400);

    // 4. Valid JPEG base64 (FF D8 FF) succeeds
    string validJpegBase64 = "/9j/4AAQSkZJRg==";
    http:Response uploadResp = check c->post("/incident/upload", {filename: "evidence.jpg", mimeType: "image/jpeg", base64Data: validJpegBase64}, headers = adminHeaders);
    test:assertTrue(uploadResp.statusCode == 200 || uploadResp.statusCode == 201);
    json uploadResult = check uploadResp.getJsonPayload();
    string safeFilename = check uploadResult.filename;
    test:assertTrue(safeFilename.startsWith("att-"));
    test:assertTrue(safeFilename.endsWith(".jpg"));

    // 5. Create incident referencing attachment
    Incident inc = check c->post("/incident/create", {
        location: "Ratnapura Shelter Area",
        description: "Simulated flood zone with photo evidence",
        category: "FLOOD",
        severity: "HIGH",
        attachmentUrl: "/incident/attachment/" + safeFilename,
        attachmentName: "evidence.jpg"
    }, headers = adminHeaders, targetType = Incident);
    test:assertEquals(inc.attachmentName, "evidence.jpg");

    // 6. Path traversal blocked
    http:Response traversal = check c->get("/incident/attachment/..%2F..%2Fsecret.txt", headers = adminHeaders);
    test:assertEquals(traversal.statusCode, 404);

    // 7. Valid download with correct content-type
    http:Response download = check c->get("/incident/attachment/" + safeFilename, headers = adminHeaders);
    test:assertEquals(download.statusCode, 200);
    test:assertEquals(download.getHeader("content-type"), "image/jpeg");
    test:assertEquals(download.getHeader("x-content-type-options"), "nosniff");

    // Cleanup
    http:Response delInc = check c->delete("/incident/" + inc.id, headers = adminHeaders);
    test:assertEquals(delInc.statusCode, 200);
}

@test:Config {}
function testMissionLifecycleExtendedAndRecommendations() returns error? {
    http:Client c = check new ("http://localhost:8080");
    AuthResponse adminLogin = check c->post("/auth/login", {username: "admin", password: "Test-only-password-2026"}, targetType = AuthResponse);
    map<string> adminHeaders = {Authorization: "Bearer " + (adminLogin.token ?: "")};

    string suffix = uuid:createType4AsString().substring(0, 8);
    string responderUser = "resp-" + suffix;
    http:Response createResp = check c->post("/admin/users", {username: responderUser, password: "Responder-pass-2026", role: "user"}, headers = adminHeaders);
    test:assertEquals(createResp.statusCode, 201);
    AuthResponse rLogin = check c->post("/auth/login", {username: responderUser, password: "Responder-pass-2026"}, targetType = AuthResponse);
    map<string> respHeaders = {Authorization: "Bearer " + (rLogin.token ?: "")};

    // Test availability toggle
    http:Response toggleStatus = check c->put("/operations/status", {status: "BUSY"}, headers = respHeaders);
    test:assertEquals(toggleStatus.statusCode, 200);
    http:Response resetStatus = check c->put("/operations/status", {status: "AVAILABLE"}, headers = respHeaders);
    test:assertEquals(resetStatus.statusCode, 200);

    // Create and verify incident
    Incident inc = check c->post("/incident/create", {
        location: "Ratnapura",
        description: "Simulated flood rescue with recommendations",
        category: "FLOOD",
        severity: "HIGH",
        latitude: 6.68,
        longitude: 80.40
    }, headers = adminHeaders, targetType = Incident);
    Incident verified = check c->post("/incident/" + inc.id + "/verify", {decision: "VERIFIED", revision: inc.revision}, headers = adminHeaders, targetType = Incident);

    // Check smart recommendations
    http:Response recsResp = check c->get("/admin/recommend/" + verified.id, headers = adminHeaders);
    test:assertEquals(recsResp.statusCode, 200);
    json recs = check recsResp.getJsonPayload();
    test:assertTrue(recs.recommendations is json[]);

    // Assign responder
    Incident assigned = check c->patch("/incident/" + verified.id, {assignee: responderUser, revision: verified.revision}, headers = adminHeaders, targetType = Incident);
    test:assertEquals(assigned.missionStatus, "ASSIGNED");

    // Responder lifecycle: ACCEPT -> EN_ROUTE -> ON_SCENE -> COMPLETE (with outcome)
    Incident accepted = check c->post("/incident/" + assigned.id + "/mission", {action: "ACCEPT", revision: assigned.revision}, headers = respHeaders, targetType = Incident);
    test:assertEquals(accepted.missionStatus, "ACCEPTED");
    Incident enRoute = check c->post("/incident/" + accepted.id + "/mission", {action: "EN_ROUTE", revision: accepted.revision}, headers = respHeaders, targetType = Incident);
    test:assertEquals(enRoute.missionStatus, "EN_ROUTE");
    Incident onScene = check c->post("/incident/" + enRoute.id + "/mission", {action: "ON_SCENE", revision: enRoute.revision}, headers = respHeaders, targetType = Incident);
    test:assertEquals(onScene.missionStatus, "ON_SCENE");
    Incident completed = check c->post("/incident/" + onScene.id + "/mission", {action: "COMPLETE", outcome: "4 families safely relocated to community center.", revision: onScene.revision}, headers = respHeaders, targetType = Incident);
    test:assertEquals(completed.missionStatus, "COMPLETED");
    test:assertTrue(completed.completionOutcome.includes("relocated"));

    // Coordinator closes incident: CLOSE
    Incident closed = check c->post("/incident/" + completed.id + "/mission", {action: "CLOSE", revision: completed.revision}, headers = adminHeaders, targetType = Incident);
    test:assertEquals(closed.missionStatus, "CLOSED");

    // Cleanup
    http:Response delClosed = check c->delete("/incident/" + closed.id, headers = adminHeaders);
    test:assertEquals(delClosed.statusCode, 200);
}

@test:Config {}
function testChoreoAndAiIntelligenceEndpoints() returns error? {
    http:Client c = check new ("http://localhost:8080");
    AuthResponse adminLogin = check c->post("/auth/login", {username: "admin", password: "Test-only-password-2026"}, targetType = AuthResponse);
    map<string> adminHeaders = {Authorization: "Bearer " + (adminLogin.token ?: "")};

    // Choreo configuration endpoint
    http:Response choreoResp = check c->get("/auth/choreo/config");
    test:assertEquals(choreoResp.statusCode, 200);
    json choreoConfig = check choreoResp.getJsonPayload();
    test:assertEquals(choreoConfig.organization, "anvora");
    test:assertEquals(choreoConfig.application, "RescuePulse");

    // Choreo invalid token rejected
    http:Response badToken = check c->post("/auth/choreo/login", {idToken: "short"});
    test:assertEquals(badToken.statusCode, 400);

    // Choreo valid token mapping (maps strictly to citizen role)
    AuthResponse choreoAuth = check c->post("/auth/choreo/login", {idToken: "simulated-valid-jwt-token-2026", username: "choreo-citizen-test"}, targetType = AuthResponse);
    test:assertEquals(choreoAuth.status, "ok");
    test:assertEquals(choreoAuth.role, "citizen");

    // Create incident for AI tests
    Incident inc = check c->post("/incident/create", {
        location: "Ratnapura",
        description: "Severe flooding blocking main road",
        category: "FLOOD",
        severity: "HIGH",
        affectedPeople: 15,
        assistanceRequested: true
    }, headers = adminHeaders, targetType = Incident);

    // Test AI priority recommendation
    http:Response priorityResp = check c->post("/assistant/incidents/" + inc.id + "/priority", {}, headers = adminHeaders);
    test:assertTrue(priorityResp.statusCode == 200 || priorityResp.statusCode == 201);
    json priorityRec = check priorityResp.getJsonPayload();
    test:assertEquals(priorityRec.suggestedPriority, "CRITICAL");

    // Test AI duplicate detection
    http:Response dupsResp = check c->post("/assistant/incidents/" + inc.id + "/duplicates", {}, headers = adminHeaders);
    test:assertTrue(dupsResp.statusCode == 200 || dupsResp.statusCode == 201);
    json dups = check dupsResp.getJsonPayload();
    test:assertTrue(dups.duplicateCandidates is json[]);

    // Test operational trends
    http:Response trendsResp = check c->post("/assistant/trends", {}, headers = adminHeaders);
    test:assertTrue(trendsResp.statusCode == 200 || trendsResp.statusCode == 201);
    json trends = check trendsResp.getJsonPayload();
    test:assertTrue(trends.totalActiveReports is int);

    // Cleanup
    http:Response delAiInc = check c->delete("/incident/" + inc.id, headers = adminHeaders);
    test:assertEquals(delAiInc.statusCode, 200);
}
