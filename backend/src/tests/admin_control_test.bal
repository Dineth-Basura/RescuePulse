import ballerina/http;
import ballerina/test;
import ballerina/uuid;

@test:Config {}
function testAdministratorAccountControls() returns error? {
    http:Client c = check new ("http://localhost:8080");
    AuthResponse login = check c->post("/auth/login", {username: "admin", password: "Test-only-password-2026"}, targetType = AuthResponse);
    map<string> admin = {Authorization: "Bearer " + (login.token ?: "")};
    string username = "managed-" + uuid:createType4AsString().substring(0, 10);
    http:Response created = check c->post("/admin/users", {username, password: "Managed-account-2026", role: "user"}, headers = admin);
    test:assertEquals(created.statusCode, 200);
    AuthResponse responderLogin = check c->post("/auth/login", {username, password: "Managed-account-2026"}, targetType = AuthResponse);
    map<string> responder = {Authorization: "Bearer " + (responderLogin.token ?: "")};
    http:Response deniedSettings = check c->get("/admin/settings", headers = responder);
    test:assertEquals(deniedSettings.statusCode, 403);
    http:Response deniedAudit = check c->get("/admin/audit", headers = responder);
    test:assertEquals(deniedAudit.statusCode, 403);
    http:Response deniedCreate = check c->post("/admin/users", {username: "blocked", password: "Denied-account-2026"}, headers = responder);
    test:assertEquals(deniedCreate.statusCode, 403);
    http:Response protectedAccount = check c->put("/admin/users/admin/status", {enabled: false}, headers = admin);
    test:assertEquals(protectedAccount.statusCode, 400);
    http:Response suspended = check c->put("/admin/users/" + username + "/status", {enabled: false}, headers = admin);
    test:assertEquals(suspended.statusCode, 200);
    http:Response expired = check c->get("/auth/me", headers = responder);
    test:assertEquals(expired.statusCode, 401);
    http:Response deniedLogin = check c->post("/auth/login", {username, password: "Managed-account-2026"});
    test:assertEquals(deniedLogin.statusCode, 401);
    http:Response restored = check c->put("/admin/users/" + username + "/status", {enabled: true}, headers = admin);
    test:assertEquals(restored.statusCode, 200);
    AuthResponse restoredLogin = check c->post("/auth/login", {username, password: "Managed-account-2026"}, targetType = AuthResponse);
    responder = {Authorization: "Bearer " + (restoredLogin.token ?: "")};
    http:Response revoked = check c->post("/admin/users/" + username + "/revoke", {}, headers = admin);
    test:assertEquals(revoked.statusCode, 200);
    http:Response revokedSession = check c->get("/auth/me", headers = responder);
    test:assertEquals(revokedSession.statusCode, 401);
    json overview = check c->get("/admin/overview", headers = admin, targetType = json);
    test:assertTrue(overview.activeUsers is int);
    json activity = check c->get("/admin/audit", headers = admin, targetType = json);
    test:assertTrue(activity.events is json[]);
}

@test:Config {}
function testWorkspacePolicyChangesAndConflictProtection() returns error? {
    http:Client c = check new ("http://localhost:8080");
    AuthResponse login = check c->post("/auth/login", {username: "admin", password: "Test-only-password-2026"}, targetType = AuthResponse);
    map<string> admin = {Authorization: "Bearer " + (login.token ?: "")};
    WorkspacePolicy previous = adminState.policy.clone();
    WorkspacePolicy changed = previous.clone(); changed.registrationOpen = false; changed.aiEnabled = false; changed.aiHourlyLimit = 5;
    http:Response saved = check c->put("/admin/settings", changed, headers = admin);
    http:Response deniedSignup = check c->post("/auth/signup", {username: "closed-registration", password: "Registration-test-2026"});
    http:Response stale = check c->put("/admin/settings", changed, headers = admin);
    WorkspacePolicy restore = previous.clone(); restore.revision = adminState.policy.revision;
    http:Response restored = check c->put("/admin/settings", restore, headers = admin);
    test:assertEquals(saved.statusCode, 200);
    test:assertEquals(deniedSignup.statusCode, 403);
    test:assertEquals(stale.statusCode, 409);
    test:assertEquals(restored.statusCode, 200);
}

@test:Config {}
function testLegacyAccountDefaults() returns error? {
    json stored = {username: "legacy", password: "existing-hash", role: "user"};
    User user = check stored.cloneWithType();
    test:assertTrue(user.enabled);
    test:assertEquals(user.lastLogin, "");
}
